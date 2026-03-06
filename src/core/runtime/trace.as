namespace UiNav {
namespace Trace {

    [Setting hidden name="UiNav trace: enabled"]
    bool S_Enabled = false;

    [Setting hidden name="UiNav trace: max entries"]
    uint S_MaxEntries = 200;

    class Entry {
        uint ms;
        string msg;
    }

    array<Entry@> g_Buf;
    uint g_NextIx = 0;
    bool g_Filled = false;

    bool Enabled() { return S_Enabled && S_MaxEntries > 0; }

    void Clear() {
        g_Buf.RemoveRange(0, g_Buf.Length);
        g_NextIx = 0;
        g_Filled = false;
    }

    void Add(const string &in msg) {
        if (!Enabled()) return;

        if (g_Buf.Length > S_MaxEntries) {
            Clear();
        }

        auto e = Entry();
        e.ms = Time::Now;
        e.msg = msg;

        if (g_Buf.Length < S_MaxEntries) {
            g_Buf.InsertLast(e);
            return;
        }

        @g_Buf[g_NextIx] = e;
        g_NextIx = (g_NextIx + 1) % S_MaxEntries;
        g_Filled = true;
    }

    string _KindStr(BackendKind k) {
        if (k == BackendKind::ControlTree) return "ControlTree";
        if (k == BackendKind::ML) return "ML";
        return "None";
    }

    string _FmtRef(NodeRef@ r) {
        if (r is null) return "ref=null";
        string s = "kind=" + _KindStr(r.kind) + " dbg=" + r.debug;
        if (r.kind == BackendKind::ControlTree) {
            s += " ov=" + r.overlay + " root=" + r.rootIx + " selector=" + r.selector;
        } else if (r.kind == BackendKind::ML) {
            s += " src=" + int(r.source) + " layer=" + r.layerIx + " selector=" + r.selector;
        }
        return s;
    }

    void Ev(const string &in op, Target@ t, NodeRef@ r = null, const string &in extra = "") {
        if (!Enabled()) return;
        string name = (t is null) ? "(null)" : t.name;
        string msg = op + " target=" + name;
        if (extra.Length > 0) msg += " " + extra;
        if (r !is null) msg += " " + _FmtRef(r);
        Add(msg);
    }

    void DumpToLog(const string &in header = "UiNav Trace") {
        if (!Enabled()) {
            log("UiNav trace is disabled", LogLevel::Info, -1, "UiNav::Trace::DumpToLog");
            return;
        }

        log(header + " (entries=" + g_Buf.Length + " max=" + S_MaxEntries + ")", LogLevel::Info, -1, "UiNav::Trace::DumpToLog");

        uint n = g_Buf.Length;
        if (n == 0) return;

        if (!g_Filled) {
            for (uint i = 0; i < n; ++i) {
                auto e = g_Buf[i];
                if (e is null) continue;
                log(tostring(e.ms) + " " + e.msg, LogLevel::Info, -1, "UiNavTrace");
            }
            return;
        }

        for (uint i = 0; i < n; ++i) {
            uint ix = (g_NextIx + i) % n;
            auto e = g_Buf[ix];
            if (e is null) continue;
            log(tostring(e.ms) + " " + e.msg, LogLevel::Info, -1, "UiNavTrace");
        }
    }

}
}
