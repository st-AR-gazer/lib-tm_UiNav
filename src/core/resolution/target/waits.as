namespace UiNav {
    OpResult@ WaitForTargetEx(Target@ t, int timeoutMs = 4000, int pollMs = 33) {
        if (timeoutMs < 0) timeoutMs = 0;
        if (pollMs < 1) pollMs = 1;
        if (pollMs > 1000) pollMs = 1000;

        uint startedAt = Time::Now;
        OpResult@ last = null;
        uint until = Time::Now + uint(timeoutMs);
        while (Time::Now < until) {
            @last = UiNav::IsReadyEx(t);
            if (last !is null && last.Ok()) {
                UiNav::Metrics::Record("wait_for_target", Time::Now - startedAt);
                return last;
            }
            yield(pollMs);
        }

        OpResult@ res = OpResult();
        res.status = OpStatus::TimedOut;
        res.reason = "timeout";
        if (last !is null) {
            res.kind = last.kind;
            @res.ref = last.ref;
        }
        UiNav::Metrics::Record("wait_for_target", Time::Now - startedAt);
        return res;
    }

    bool WaitForTarget(Target@ t, int timeoutMs = 4000, int pollMs = 33) {
        auto res = WaitForTargetEx(t, timeoutMs, pollMs);
        return res !is null && res.Ok();
    }
}
