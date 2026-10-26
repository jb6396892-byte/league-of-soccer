extends RefCounted
## Shared gameplay numbers: the interactive match and simulator use this file.

enum Kind { RUNNER, GUARD, CHARGER, STRIKER, KEEPER, WARDEN }

const NAMES := ["疾风", "刺猬", "月影", "旗帜", "铁闸", "镇域"]
const COLORS := [Color("#dff78d"), Color("#ffc66b"), Color("#bd9cff"), Color("#ff95c1"), Color("#8de7f0"), Color("#86d6a3")]
const PASSIVES := ["移动速度 +5%", "判定 +10% · 移速 -5%", "移动速度 -10%", "移速 -5% · W 移动施法", "禁区门将 · Q 范围扑救", "己半场 +10% / 敌半场 -15%"]
const W_NAMES := ["疾跑", "迟滞力场", "蓄力冲刺", "破阵投掷", "禁区威慑", "镇守领域"]
const W_DETAILS := ["加速 2 秒 / CD 12 秒", "减速 30% · 5 秒 / CD 20 秒", "移动蓄力，松开冲刺 / CD 4 秒", "移动施法 · 眩晕 1 秒 / CD 10 秒", "前方减速 20% · 5 秒 / CD 30 秒", "鼠标放置 · 减速 30% / 持续 12 秒 · CD 60 秒"]
const SPEED := [1.05, 0.95, 0.9, 0.95, 1.0, 1.0]
const HIT_SCALE := [1.0, 1.1, 1.0, 1.0, 1.0, 1.0]
const DURATION := [2.0, 5.0, 0.0, 0.0, 5.0, 12.0]
const COOLDOWN := [12.0, 20.0, 4.0, 10.0, 30.0, 60.0]
const DOMAIN_RADIUS := 10.0
const DOMAIN_RANGE := 30.0
const SPRINT_MULTIPLIER := 1.35
const SLOW_RADIUS := 4.5
const SLOW_MULTIPLIER := 0.7
const CHARGE_DURATION := 0.6
const AI_CHARGE_MIN_FRACTION := 0.7
const DASH_MIN_DISTANCE := 3.0
const DASH_MAX_DISTANCE := 9.0
const DASH_SPEED := 18.0
const THROW_WINDUP := 0.5
const THROW_RANGE := 18.0
const THROW_SPEED := 20.0
const THROW_RADIUS := 0.55
const STUN_SECONDS := 1.0
const KEEPER_SLOW_RADIUS := 8.0
const KEEPER_CONE_HALF_ANGLE := PI / 3.0
const KEEPER_SLOW_MULTIPLIER := 0.8
const SAVE_REACH := 3.5
const SAVE_HEIGHT := 3.5
const SAVE_WINDOW := 0.7
const SAVE_COOLDOWN := 1.5
