# survivor_mvp

- 本插件提供生还者 MVP 数据显示，并允许选择是否显示特感、丧尸、友伤、总伤害、爆头率，是否显示团灭次数，将 MVP 数据显示给指定团队等功能

# 插件指令
`!mvp`：将生还者 MVP 信息显示给指定客户端

# Cvars
``` Java
// 是否允许显示生还者 MVP 数据
mvp_allow_show 1
// 将生还者 MVP 数据显示给哪个团队（0：所有，1：旁观者，2：生还者，3：感染者）
mvp_witch_team_show 0
// 是否允许显示击杀特感信息
mvp_allow_show_si 1
// 是否允许显示击杀丧尸信息
mvp_allow_show_ci 1
// 是否允许显示友伤信息
mvp_allow_show_ff 1
// 是否允许显示总伤害信息
mvp_allow_show_damage 1
// 是否允许显示爆头率信息
mvp_allow_show_acc 1
// 是否在团灭时显示团灭次数
mvp_show_fail_count 1
// 是否在过关或团灭时显示 MVP 详细信息（特感杀手，清尸狂人，队友杀手等）
mvp_show_details 1
```

# 效果图示
![生还者 MVP 效果图示](/SurvivorMVP/survivor_mvp.png)

# 更新日志
- 2022-12-21：上传插件与 readme 文件
