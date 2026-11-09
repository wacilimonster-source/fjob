"""Validate the handoff contracts and independently check reference fixture arithmetic.

Run with Python 3.10+ and PyYAML, jsonschema, openapi-spec-validator installed.
This validates specification fixtures, not a production finance implementation.
"""

from copy import deepcopy
from decimal import Decimal, ROUND_HALF_UP, localcontext
from pathlib import Path
import json
import re

import yaml
from jsonschema import Draft202012Validator, FormatChecker, ValidationError
from openapi_spec_validator import validate


ROOT = Path(__file__).resolve().parents[1]


def read_json(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def display(value):
    rounded = value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return format(abs(rounded) if rounded == 0 else rounded, ".2f")


def wage(data):
    monthly = Decimal(data["monthlyCny"])
    if monthly == 0:
        return Decimal(0)
    if data["monthlyPaidSeconds"] == 0:
        raise ValueError("invalidSchedule")
    return monthly * data["elapsedPaidSeconds"] / data["monthlyPaidSeconds"]


def allocation(data):
    return (Decimal(data["monthlyCny"]) / data["monthDays"]
            * data["elapsedDaySeconds"] / data["daySeconds"])


def plain(value):
    """Decimal without exponent or redundant trailing zeros."""
    text = format(value.normalize(), "f")
    return "0" if text in ("-0", "0") else text


def fund_held(data):
    return (Decimal(data["nav"]) - Decimal(data["cost"])) * Decimal(data["quantity"])


def fund_daily(data):
    return (Decimal(data["nav"]) - Decimal(data["previousNav"])) * Decimal(data["quantity"])


def check_case(case):
    data = case["input"]
    expected = case["expected"]
    operation = case["operation"]
    try:
        if operation == "wage":
            result = wage(data)
        elif operation in ("allocation", "loanBreakdown"):
            result = allocation(data)
            if operation == "loanBreakdown":
                principal = data["principalCny"]
                principal_result = allocation({**data, "monthlyCny": principal}) if principal is not None else None
                interest_result = result - principal_result if principal_result is not None else None
                assert expected["principalCny"] == (display(principal_result) if principal_result is not None else None)
                assert expected["interestCny"] == (display(interest_result) if interest_result is not None else None)
        elif operation == "pnl":
            quantity = Decimal(data["quantity"])
            result = ((Decimal(data["price"]) - Decimal(data["baseline"])) * quantity
                      if quantity else Decimal(0))
        elif operation == "dashboard":
            salary = wage({"monthlyCny": data["monthlySalaryCny"],
                           "monthlyPaidSeconds": data["monthlyPaidSeconds"],
                           "elapsedPaidSeconds": data["elapsedPaidSeconds"]})
            expense = allocation({**data, "monthlyCny": str(Decimal(data["housingMonthlyCny"]) + Decimal(data["carMonthlyCny"]))})
            result = salary - expense + sum(
                Decimal(data[key]) if data.get(key) is not None else Decimal(0)
                for key in ["stockDailyCny", "goldDailyCny", "fundDailyCny"]
            )
            fund_known = data.get("fundDailyKnown", True)
            completeness = "partial" if (
                any(data[key] is None for key in ["stockDailyCny", "goldDailyCny"])
                or not fund_known
            ) else "complete"
            assert completeness == expected["completeness"]
        elif operation == "fundHeld":
            result = fund_held(data)
            assert expected.get("exact") == plain(result), (case["id"], plain(result))
        elif operation == "fundDaily":
            result = fund_daily(data)
            assert expected.get("exact") == plain(result), (case["id"], plain(result))
        elif operation == "fundDailyStale":
            # The latest NAV predates the statistics day, so today's move is
            # unknown; the held valuation still uses the latest NAV.
            assert expected.get("unknown") is True
            assert display(fund_held(data)) == expected["heldDisplayCny"]
            return
        elif operation == "monthAllocation":
            daily = Decimal(data["monthlyCny"]) / data["monthDays"]
            result = daily * data["monthDays"]
        elif operation == "closedStockDay":
            assert data["tradingDate"] < data["statisticsDate"]
            result = Decimal(0)
        elif operation == "splitWage":
            result = sum(wage(part) for part in data["parts"])
        elif operation == "housingSwitch":
            assert sum(part["fullDays"] for part in data["parts"]) == data["monthDays"]
            result = sum(Decimal(part["monthlyCny"]) / data["monthDays"] * part["fullDays"] for part in data["parts"])
        elif operation == "sum":
            result = sum(Decimal(value) for value in data["values"])
        else:
            raise AssertionError(f"Unknown fixture operation {operation}")
    except ValueError as error:
        assert expected.get("error") == str(error), case["id"]
        return
    assert "error" not in expected, case["id"]
    assert display(result) == expected["displayCny"], (case["id"], result, expected)


def check_widget_schemas():
    v1 = read_json("contracts/widget-snapshot.schema.json")
    v2 = read_json("contracts/widget-snapshot-v2.schema.json")
    for schema in (v1, v2):
        Draft202012Validator.check_schema(schema)
    v1_validator = Draft202012Validator(v1, format_checker=FormatChecker())
    v2_validator = Draft202012Validator(v2, format_checker=FormatChecker())

    old_snapshot = read_json("fixtures/widget-snapshot.json")
    v1_validator.validate(old_snapshot)
    new_snapshot = read_json("fixtures/widget-snapshot-v2.json")
    v2_validator.validate(new_snapshot)

    # v2 must require the new key and reject a v1-shaped amount map.
    missing_key = deepcopy(new_snapshot)
    del missing_key["amounts"]["stockFundDaily"]
    try:
        v2_validator.validate(missing_key)
    except ValidationError:
        pass
    else:
        raise AssertionError("v2 schema accepted an amount map without stockFundDaily")

    # v1 must keep rejecting the v2-only key so an old parser cannot silently
    # accept a payload it does not render.
    try:
        v1_validator.validate(new_snapshot)
    except ValidationError:
        pass
    else:
        raise AssertionError("v1 schema accepted a v2 amount map")

    for schema, snapshot in ((v1_validator, old_snapshot), (v2_validator, new_snapshot)):
        private = deepcopy(snapshot)
        private["privacy"] = True
        private["amounts"] = {key: None for key in snapshot["amounts"]}
        schema.validate(private)
        leaking = {**snapshot, "privacy": True}
        try:
            schema.validate(leaking)
        except ValidationError:
            pass
        else:
            raise AssertionError("Privacy schema accepted non-null amounts")


def main():
    check_widget_schemas()

    api = yaml.safe_load((ROOT / "contracts/market-gateway.openapi.yaml").read_text(encoding="utf-8"))
    validate(api)
    cases = read_json("fixtures/calculation-cases.json")["cases"]
    assert len({case["id"] for case in cases}) == len(cases)
    with localcontext() as context:
        context.prec = 40
        for case in cases:
            check_case(case)

    for path in [ROOT / "README.md", *sorted((ROOT / "docs").glob("*.md"))]:
        for target in re.findall(r"\]\(([^)]+)\)", path.read_text(encoding="utf-8")):
            if re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", target) or target.startswith("#"):
                continue
            assert (path.parent / target.split("#")[0]).exists(), (path, target)
    assert (ROOT / "prototype/source.html").stat().st_size < 1_000_000
    print(f"PASS {len(cases)} reference calculations, OpenAPI, widget v1/v2 schemas, privacy rejection and document links")


if __name__ == "__main__":
    main()
