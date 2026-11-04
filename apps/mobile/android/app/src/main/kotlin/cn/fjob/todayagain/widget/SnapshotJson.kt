package cn.fjob.todayagain.widget

/**
 * Minimal JSON reader for the widget payload.
 *
 * The snapshot comes from the app's own Dart encoder, so a full JSON library is
 * unnecessary; keeping the parser in pure Kotlin lets the JVM unit tests cover
 * the contract without an Android runtime.
 */
internal object SnapshotJson {
    fun parse(text: String): Any? {
        val parser = Parser(text)
        val value = parser.readValue()
        parser.skipWhitespace()
        require(parser.atEnd()) { "trailing data at ${parser.position}" }
        return value
    }

    private class Parser(private val text: String) {
        var position: Int = 0
            private set

        fun atEnd(): Boolean = position >= text.length

        fun skipWhitespace() {
            while (position < text.length && text[position].isWhitespace()) {
                position++
            }
        }

        fun readValue(): Any? {
            skipWhitespace()
            require(position < text.length) { "unexpected end of JSON" }
            return when (val char = text[position]) {
                '{' -> readObject()
                '[' -> readArray()
                '"' -> readString()
                't' -> readLiteral("true", true)
                'f' -> readLiteral("false", false)
                'n' -> readLiteral("null", null)
                '-', in '0'..'9' -> readNumber()
                else -> throw IllegalArgumentException("unexpected '$char' at $position")
            }
        }

        private fun readObject(): Map<String, Any?> {
            expect('{')
            val result = LinkedHashMap<String, Any?>()
            skipWhitespace()
            if (peek() == '}') {
                position++
                return result
            }
            while (true) {
                skipWhitespace()
                val key = readString()
                skipWhitespace()
                expect(':')
                result[key] = readValue()
                skipWhitespace()
                when (peek()) {
                    ',' -> position++
                    '}' -> {
                        position++
                        return result
                    }
                    else -> throw IllegalArgumentException("expected , or } at $position")
                }
            }
        }

        private fun readArray(): List<Any?> {
            expect('[')
            val result = ArrayList<Any?>()
            skipWhitespace()
            if (peek() == ']') {
                position++
                return result
            }
            while (true) {
                result.add(readValue())
                skipWhitespace()
                when (peek()) {
                    ',' -> position++
                    ']' -> {
                        position++
                        return result
                    }
                    else -> throw IllegalArgumentException("expected , or ] at $position")
                }
            }
        }

        private fun readString(): String {
            expect('"')
            val builder = StringBuilder()
            while (position < text.length) {
                val char = text[position++]
                when (char) {
                    '"' -> return builder.toString()
                    '\\' -> {
                        require(position < text.length) { "escape at end" }
                        when (val escape = text[position++]) {
                            '"' -> builder.append('"')
                            '\\' -> builder.append('\\')
                            '/' -> builder.append('/')
                            'b' -> builder.append('\b')
                            'f' -> builder.append('\u000C')
                            'n' -> builder.append('\n')
                            'r' -> builder.append('\r')
                            't' -> builder.append('\t')
                            'u' -> {
                                require(position + 4 <= text.length) { "bad unicode escape" }
                                val code = text.substring(position, position + 4).toInt(16)
                                builder.append(code.toChar())
                                position += 4
                            }
                            else -> throw IllegalArgumentException("bad escape \\$escape")
                        }
                    }
                    else -> builder.append(char)
                }
            }
            throw IllegalArgumentException("unterminated string")
        }

        private fun readNumber(): Number {
            val start = position
            if (peek() == '-') position++
            while (position < text.length && text[position].isDigit()) position++
            var fractional = false
            if (position < text.length && text[position] == '.') {
                fractional = true
                position++
                while (position < text.length && text[position].isDigit()) position++
            }
            if (position < text.length &&
                (text[position] == 'e' || text[position] == 'E')
            ) {
                fractional = true
                position++
                if (position < text.length &&
                    (text[position] == '+' || text[position] == '-')
                ) {
                    position++
                }
                while (position < text.length && text[position].isDigit()) position++
            }
            val raw = text.substring(start, position)
            return if (fractional) raw.toDouble() else raw.toLong()
        }

        private fun <T> readLiteral(literal: String, value: T): T {
            require(text.startsWith(literal, position)) { "expected $literal at $position" }
            position += literal.length
            return value
        }

        private fun peek(): Char {
            require(position < text.length) { "unexpected end of JSON" }
            return text[position]
        }

        private fun expect(char: Char) {
            require(peek() == char) { "expected $char at $position" }
            position++
        }
    }
}
