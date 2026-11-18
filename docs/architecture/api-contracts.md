# V1 API 合约

状态：待实现。以下是自有框架 API 设计，不是第三方库现有 API。均为 Lua 5.1 兼容签名；模块路径根为 `framework`。基础数据 `{code, message, details?}` 表示错误；业务失败返回 `nil, error`，成功返回值或 `true`。无效开发配置可在启动时快速失败，不吞异常。

## Core 与 EventBus

```lua
App.create(config, adapters) --> app
app:start()                 --> true | nil, error
app:update(dt)
app:shutdown()              -- 幂等，逆序释放已启动服务
app:service(name)           --> service | nil, error

EventBus.create()            --> bus
bus:subscribe(topic, fn)     --> unsubscribe
bus:emit(topic, payload)     --> true | nil, error
bus:clear()

Pause.create()               --> pause
pause:acquire(reason)        --> release
pause:is_paused()            --> boolean
```

start 部分失败必须清理已启动服务。EventBus 按订阅顺序调用本次派发快照；派发中新订阅下次生效，已注销项跳过。监听器错误记录 topic/订阅来源并返回错误，其余监听器继续；嵌套 emit 进入队列，设置单次最大派发数防止事件循环。payload 按只读约定传递。unsubscribe/release 均可重复调用。

## UI

```lua
UI.create(route_config, adapter) --> ui
ui:open(route_id, data, done)     --> request_id | nil, error
ui:back(done)                    --> request_id | nil, error
ui:dialog(route_id, data, done)   --> request_id | nil, error
ui:toast(text_key, params)
ui:is_busy()                     --> boolean
ui:dispose()
```

open/back 的 done 在转场结束或失败时调用一次。dialog 的 done 在用户选择、取消或关闭时调用一次，返回 `{status="selected"|"cancelled", value?}`；加载失败为 error。没有返回历史时 back 返回 no_history。未知路由返回 unknown_route，转场中返回 busy；V1 不隐式排队。dialog 必须指向预注册 popup 路由。

所有被接受的异步请求遵循 exactly-once completion；dispose 完成尚未结束请求并标记 cancelled，调用方用生命周期 token 防止访问已释放 GUI。页面数据使用普通 table，进入页面时复制需要的数据，不把 Controller 或 GUI 节点塞进路由参数。

```lua
Theme.validate(tokens, resources) --> theme | nil, error
Theme.apply(root, bindings, theme) -- 只在所属 GUI context 调用
Button.create(druid, nodes, options) --> component
component:set_enabled(enabled)
component:dispose()
CurrencyBar:set_value(amount)       -- 只展示，不持有经济状态
```

通用页面适配层封装生命周期转发，不把整个 Druid API 再复制一遍。控件回调、全局应用事件、Defold 消息分别有明确用途，避免多层重复广播。

## Save / Settings / Localization

```lua
Save.create(storage, options) --> save
save:load(slot, defaults, migrations, validate) --> snapshot, meta | nil, error
save:commit(slot, snapshot)                    --> revision | nil, error
save:flush()                                  --> true | nil, error
save:dispose()

-- storage 必须说明完成语义；未来异步后端需要另设异步契约
storage:read(slot)               --> envelope | nil, error
storage:write(slot, envelope)    --> true | nil, error

Settings:set(key, value)         --> true | nil, error
Settings:get(key)                --> value
Localization:set_locale(locale) --> true | nil, error
Localization:t(key, params)     --> string
```

load 返回副本，meta 含 source/default/migrated 等状态。初次无档可正常使用 defaults；损坏/未来版本/迁移失败明确返回错误，并让调用方选择恢复，不静默覆盖。迁移 `migrate_n_to_n1(copy)` 必须逐级执行，每一步校验，最后才提交新档。V1 只承诺本地同步适配器报告的写入结果；浏览器持久化跨刷新可靠性必须由集成测试证明。

Settings 校验已知键和范围。Localization 回退顺序：所选语言 → 默认语言 → `[key]`，缺失键记录日志。V1 支持命名参数插值，中英文语言切换触发 GUI 自身消息更新；不实现完整 ICU 语法。

## Platform / Ads / Audio / Analytics

```lua
Platform:capabilities() --> {rewarded_ads=false, safe_area=false, ...}
Platform:safe_area()    --> {left=0,right=0,top=0,bottom=0} -- 逻辑坐标

Ads:show_rewarded(placement, done) --> request_id | nil, error
Ads:cancel(request_id)
-- done({request_id=..., status="completed"|"cancelled"|"unavailable"|"error", error?})

Audio:play_music(id, options) --> true | nil, error
Audio:play_sfx(id, options)   --> handle | nil, error
Audio:set_volume(group, value) --> true | nil, error
Audio:set_muted(muted)
Analytics:track(event_name, properties) --> true | nil, error
```

Ads 并发返回 busy；unsupported adapter 接受请求后报告 unavailable，绝不模拟成功。Mock 可配置四种结果、延迟、超时和重复回调以验证包装层。request_id 生命周期全局唯一到应用会话，不仅按 placement 去重。用户关闭页面后回调不操作旧节点；已获得的奖励由存活 Controller 处理。

Analytics 默认日志实现不执行网络发送。平台返回的物理像素边距由适配器转为 GUI 逻辑坐标，不能直接混用。浏览器普通页无原生边距能力时明确返回零并报告 capability。

## 后续玩法库（Framework V1 后）

```lua
Economy.create(config) --> state
Economy.add(state, currency, amount) --> true | nil, error
Economy.spend(state, currency, amount) --> true | nil, error
Inventory.add(state, item_id, count) --> true | nil, error
Upgrade.get_cost(config, level) --> cost
Production.advance(state, config, elapsed) --> result | nil, error
Offline.calculate(last_time, now, cap, config) --> reward | nil, error
```

校验有限数值、非负数量、整数计数；余额使用明确的整数单位并控制在精确整数范围内。不能先扣款再发现升级条件失败：Controller 先验证整笔操作，再统一提交 state 和存档。离线收益时间来自注入时钟，负时间归零、超过上限截断，以领取记录避免重复发放；本地时钟方案不承诺防作弊。
