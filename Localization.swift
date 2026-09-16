import SwiftUI

/// Display language for the panel. Identification never depends on it.
enum Lang: String, CaseIterable, Identifiable {
    case en
    case zh

    var id: String { rawValue }
    var pickerLabel: String { self == .en ? "English" : "繁體中文" }
}

private struct LangKey: EnvironmentKey {
    static let defaultValue: Lang = .en
}

extension EnvironmentValues {
    var lang: Lang {
        get { self[LangKey.self] }
        set { self[LangKey.self] = newValue }
    }
}

enum L10n {
    enum Key {
        case opponent, yourSide, weak, resist, immune, megaWeak
        case unidentified, ability, hidden, bst, speed
        case hideMirror, showMirror
        case damage, damageNote, usageCredit, baseForm
    }

    private static let strings: [Key: (en: String, zh: String)] = [
        .opponent: ("OPPONENT", "對手"),
        .yourSide: ("YOUR SIDE", "我方"),
        .weak: ("WEAK", "弱點"),
        .resist: ("RESIST", "抵抗"),
        .immune: ("IMMUNE", "免疫"),
        .megaWeak: ("→WEAK", "→弱點"),
        .unidentified: ("Unidentified", "未辨識"),
        .ability: ("ABILITY", "特性"),
        .hidden: ("HIDDEN", "隱藏"),
        .bst: ("BST", "總和"),
        .damage: ("DAMAGE", "傷害"),
        .baseForm: ("BASE", "原形"),
        .damageNote: ("no Stat Points, neutral nature, no item",
                      "無能力點數、無性格加成、無道具"),
        .usageCredit: ("Move usage: championsbattledata.com",
                       "招式使用率：championsbattledata.com"),
        .speed: ("SPEED", "速度"),
        .hideMirror: ("Hide screen", "隱藏畫面"),
        .showMirror: ("Show screen", "顯示畫面"),
    ]

    static func text(_ key: Key, _ lang: Lang) -> String {
        guard let pair = strings[key] else { return "" }
        return lang == .zh ? pair.zh : pair.en
    }

    static func format(_ format: BattleFormat, _ lang: Lang) -> String {
        guard lang == .zh else { return format.label }
        switch format {
        case .idle: return "未在對戰"
        case .singles: return "單打"
        case .doubles: return "雙打"
        }
    }

    private static let typeZh: [String: String] = [
        "normal": "一般", "fire": "火", "water": "水", "electric": "電",
        "grass": "草", "ice": "冰", "fighting": "格鬥", "poison": "毒",
        "ground": "地面", "flying": "飛行", "psychic": "超能力", "bug": "蟲",
        "rock": "岩石", "ghost": "幽靈", "dragon": "龍", "dark": "惡",
        "steel": "鋼", "fairy": "妖精",
    ]

    static func type(_ type: String, _ lang: Lang) -> String {
        lang == .zh ? (typeZh[type] ?? type) : type.uppercased()
    }

    private static let statZh: [String: String] = [
        "HP": "HP", "Atk": "攻擊", "Def": "防禦", "SpA": "特攻", "SpD": "特防", "Spe": "速度",
    ]

    /// Takes the English label from `BaseStats.ordered`.
    static func stat(_ label: String, _ lang: Lang) -> String {
        lang == .zh ? (statZh[label] ?? label) : label
    }
}
