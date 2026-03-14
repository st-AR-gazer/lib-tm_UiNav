namespace UiNav {
    OpResult@ WaitForTargetEx(Target@ t, int timeoutMs = 4000, int pollMs = 33) {
        if (timeoutMs < 0) timeoutMs = 0;
        if (pollMs < 1) pollMs = 1;
        if (pollMs > 1000) pollMs = 1000;

        uint startedAt = Time::Now;
        uint attempts = 0;
        OpResult@ last = null;
        @last = UiNav::IsReadyEx(t);
        attempts++;
        if (last !is null && last.Ok()) {
            last.waitedMs = Time::Now - startedAt;
            last.attempts = attempts;
            UiNav::Metrics::Record("wait_for_target", Time::Now - startedAt);
            return last;
        }
        if (last !is null && last.status == OpStatus::InvalidTarget) {
            last.waitedMs = Time::Now - startedAt;
            last.attempts = attempts;
            UiNav::Metrics::Record("wait_for_target", Time::Now - startedAt);
            return last;
        }
        if (timeoutMs == 0) {
            if (last !is null) {
                last.waitedMs = Time::Now - startedAt;
                last.attempts = attempts;
                last.lastStatus = last.status;
            }
            UiNav::Metrics::Record("wait_for_target", Time::Now - startedAt);
            return last;
        }

        uint until = startedAt + uint(timeoutMs);
        while (Time::Now < until) {
            yield(pollMs);
            @last = UiNav::IsReadyEx(t);
            attempts++;
            if (last !is null && last.Ok()) {
                last.waitedMs = Time::Now - startedAt;
                last.attempts = attempts;
                UiNav::Metrics::Record("wait_for_target", Time::Now - startedAt);
                return last;
            }
        }

        string detail = "no readiness result was produced";
        if (last !is null) {
            detail = "last status=" + UiNav::_OpStatusName(last.status);
            if (last.reason.Length > 0) detail += " reason=" + last.reason;
            if (last.detail.Length > 0 && last.detail != last.reason) detail += " detail=" + last.detail;
        }

        auto res = UiNav::_MakeOpResult(OpStatus::TimedOut, last is null ? null : last.ref,
            "timed out waiting for target", "", "wait_timed_out", detail);
        if (last !is null) {
            res.kind = last.kind;
            res.lastStatus = last.status;
            @res.ref = last.ref;
        } else {
            res.lastStatus = OpStatus::ResolveFailed;
        }
        res.waitedMs = Time::Now - startedAt;
        res.attempts = attempts;
        UiNav::Metrics::Record("wait_for_target", Time::Now - startedAt);
        return res;
    }

    bool WaitForTarget(Target@ t, int timeoutMs = 4000, int pollMs = 33) {
        auto res = WaitForTargetEx(t, timeoutMs, pollMs);
        return res !is null && res.Ok();
    }
}
