-- Analytics 抽象：统一的埋点出口。
--
-- 业务侧只调用 track(event, params)，具体落盘/上报由注入的 logger 决定。
-- 默认 logger 是 print，方便本地调试；生产环境可注入上报通道。
--
-- track(event, params) -> true | nil, error
-- flush()               -> true          (通知 logger 落盘)

local M = {}

function M.create(options)
    options = options or {}
    local self = {
        logger = options.logger, -- 注入：function(event, params, meta)
        out = options.out or print,
        seq = 0,
        enabled = options.enabled ~= false,
    }

    local function now_ms()
        -- os.clock 是 CPU 时间，不适合墙钟；os.time 只有秒。这里用秒 + 顺序号。
        return os.time()
    end

    function self:track(event, params)
        if not self.enabled then return true end
        if type(event) ~= "string" or event == "" then
            return nil, { code = "invalid_event", message = "event must be a non-empty string" }
        end
        self.seq = self.seq + 1
        local meta = { seq = self.seq, ts = now_ms() }
        local payload = type(params) == "table" and params or nil

        if self.logger then
            local ok, err = pcall(self.logger, event, payload, meta)
            if not ok then
                self.out("[Analytics:" .. event .. "] logger error: " .. tostring(err))
            end
        else
            local extra = ""
            if payload then
                local parts = {}
                for k, v in pairs(payload) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
                table.sort(parts)
                extra = " " .. table.concat(parts, " ")
            end
            self.out("[Analytics:" .. event .. "]" .. extra)
        end
        return true
    end

    function self:flush()
        if self.logger and self.logger.flush then
            pcall(self.logger.flush)
        end
        return true
    end

    function self:set_enabled(enabled)
        self.enabled = not not enabled
    end

    function self:get_seq()
        return self.seq
    end

    return self
end

return M
