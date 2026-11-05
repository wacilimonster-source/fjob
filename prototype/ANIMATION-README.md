# 动画原型交接

版本 1.0 · 2026-11-05 · 对应[拍拍他与下班离场设计](../docs/09-design-comfort-and-clock-out.md)。

## 文件入口

| 文件 | 用途 |
| --- | --- |
| [animation.html](animation.html) | 浏览器直接打开的完整原型 |
| [animation-source.html](animation-source.html) | 可编辑HTML/CSS/Canvas源片段，含动画控制器 |
| [animation-timeline.json](animation-timeline.json) | 导出的时长、接触点时间、关键帧采样点和触控区域 |
| [animation-keyframes](animation-keyframes) | 13张固定时间的手机画面参考PNG |

原型完整代码内联，无构建依赖。使用本地浏览器打开animation.html即可操作。source.html中的`fm-timing-data`是时间参数源，修改后同步导出JSON及重新生成独立HTML。

## 播放与审稿

1. 点手机画面里的“拍拍他”，或直接点击人物头肩，查看3.2秒拍肩与回应。正在播放时连点会被忽略。
2. 点演示台“下班离场”，查看2.2秒停手、起身、提包和走出画面。
3. 点“拍拍中下班”，前1500ms播放拍肩，1500ms切到下班并开始离场，整段3700ms。
4. 用“直接查看稳态”选择下班后、上班前、休息日或排班未知，验证空工位与禁用状态。
5. 点暂停、拖动滑块、点击毫秒标记或使用±100ms，检查同一帧。0.5×以半速播放，时间轴仍显示片段逻辑毫秒。
6. 切换盈利/亏损/报价未知、语气、减少动效及房车图层，比较不同组合。语气在每次接受拍肩时锁定，本次回应期间不会被切换打断。
7. 使用“跨午夜仍在岗”和“夜班02:00下班”两个预设事件，查看跨夜工作及离场的视觉目标。

拍肩结束后可再次点击。演示台的片段按钮可以重置并重播，用于审稿。播放中暂停会保留姿态，切换稳态则结束当前片段。

## 时间与状态

| 片段 | 常规总时长 | 低动效 |
| --- | --- | --- |
| pat | 3200ms | 静态抬眼、腮红、回应2400ms |
| departure | 2200ms | 立即空工位 |
| race | 3700ms | 前1500ms静态回应，随后空工位 |

关键绘制函数为`view()`和`draw(view)`。前者根据片段时间计算人物存在性、抬眼、头部压缩、手掌透明度、起身与行走位移，后者绘制对应帧。`tick()`只推进动画播放时钟。

按钮`requestPat()`按逻辑Presence门控。离场中逻辑Presence已经是emptyDesk，渲染器暂时绘制正在走出的角色，用户此时无法继续拍肩。拍肩和离场均为一次性片段，结束保持终态。

财务金额是审稿用固定快照，盈亏选择对应三套示例值。房车复选框用于图层审稿。预设事件模拟排班边界，正式App由真实排班上下文驱动同样的视觉状态。原型不提供数据库、计薪计算、行情接入或原生触觉实现。

系统减少动态效果与原型开关取逻辑或。启用后仍有静态回应和文字反馈。页面隐藏时取消瞬态，重新可见时采用当前稳态，不补播。

## 自动采样接口

原型在所属window暴露`fjobAnimationPrototype`。独立HTML由渲染器放在iframe里，Playwright先取得该iframe的Frame再调用接口。

```javascript
const api = window.fjobAnimationPrototype;

api.setPhase('working');
api.playPat();       // 返回accepted布尔值，忙碌/不在岗时返回false
api.pause();
api.seek(210);       // 当前片段定位到210ms，自动暂停
api.inspect();      // 返回片段时间、有效phase、presence、手掌/角色参数

api.selectClip('departure'); // 选片段并暂停在0ms
api.seek(1400);              // 正在走出画面
api.seek(2200);              // 空工位终态

api.selectClip('race');
api.seek(1490);              // 正在拍肩
api.seek(1500);              // 拍肩被下班中断，进入离场
```

接口支持的phase为working、breakTime、afterShift、beforeShift、restDay、unknown。片段为pat、departure、race。`inspect()`中的accepted用于验证原型的重复点击拦截，无财务含义。

## 关键帧列表

- 拍肩为`pat-0000`、`pat-0120`、`pat-0210`、`pat-0410`、`pat-0720`、`pat-1200`、`pat-2600`、`pat-3200`。
- 离场为`departure-0000`、`departure-0560`、`departure-0860`、`departure-1400`、`departure-2200`。

PNG对应包含标题、固定金额、场景和反馈区的完整手机画面。实施原生小部件时，按设计规格用共享Painter生成独立办公室静态资源。

## 本轮验证

使用Playwright与Edge验证了正常拍肩、20次重复触发拦截、210/1200ms姿态参数、回应语气锁定、四种空位状态、午休、1400ms行走和2200ms空位、中途下班、低动效、房车四种组合、真实时间播放、暂停、午夜在岗及320/360/440/736像素宽布局。

13张PNG由原型定位到指定毫秒后采样。浏览器执行未记录JavaScript pageerror。生产App的排班、生命周期、原生触觉和小部件验收按设计文档执行。
