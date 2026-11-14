local _ = require("gettext")
return {
    fullname = _("小小学习家"),
    description = _([[小学 1-6 年级语文数学答题练习，支持多省/多教材、星星积分、连续打卡、奖章、错题本和可选 AI 变种强化。]]),
    -- Single source of truth for the plugin version. GitHub Release tags use
    -- "v" .. version (e.g. v1.3.0) and carry a kidlearn.koplugin.zip asset.
    version = "1.5.1",
}
