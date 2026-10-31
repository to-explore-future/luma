import Foundation

/// 界面文案。菜单和面板里就这些字，直接内嵌。
enum L10n {
    struct Lang {
        let code: String
        let name: String
        let strings: [String: String]
    }

    static let languages: [Lang] = [
        Lang(code: "zh-Hans", name: "简体中文", strings: [
            "backendAuto": "调光:自动", "backendSoftware": "调光:软件",
            "loginOn": "自启:开", "loginOff": "自启:关",
            "donate": "赞助", "quit": "退出", "language": "语言",
            "current": "当前屏幕", "hint": "唤醒后自动恢复",
            "hintGamma": "唤醒后自动恢复 · 软件调光：",
            "donateLine1": "软件免费，赞助随意",
            "donateLine2": "能帮到你，就是最大的动力。",
            "donateScan": "微信扫码",
        ]),
        Lang(code: "zh-Hant", name: "繁體中文", strings: [
            "backendAuto": "調光:自動", "backendSoftware": "調光:軟體",
            "loginOn": "開機啟動:開", "loginOff": "開機啟動:關",
            "donate": "贊助", "quit": "結束", "language": "語言",
            "current": "目前螢幕", "hint": "喚醒後自動恢復",
            "hintGamma": "喚醒後自動恢復 · 軟體調光：",
            "donateLine1": "軟體免費，贊助隨意",
            "donateLine2": "能幫到你，就是最大的動力。",
            "donateScan": "微信掃碼",
        ]),
        Lang(code: "en", name: "English", strings: [
            "backendAuto": "Dim: Auto", "backendSoftware": "Dim: Software",
            "loginOn": "Login: On", "loginOff": "Login: Off",
            "donate": "Donate", "quit": "Quit", "language": "Language",
            "current": "Current", "hint": "Restored after sleep",
            "hintGamma": "Restored after sleep · Software dimming: ",
            "donateLine1": "Free software, tips optional",
            "donateLine2": "If it helps you, that's all the reward I need.",
            "donateScan": "Scan with WeChat",
        ]),
        Lang(code: "ja", name: "日本語", strings: [
            "backendAuto": "調光:自動", "backendSoftware": "調光:ソフト",
            "loginOn": "ログイン:オン", "loginOff": "ログイン:オフ",
            "donate": "支援", "quit": "終了", "language": "言語",
            "current": "現在の画面", "hint": "スリープ復帰後に自動復元",
            "hintGamma": "スリープ復帰後に自動復元 · ソフト調光：",
            "donateLine1": "ソフトは無料、支援は任意",
            "donateLine2": "お役に立てることが一番の報酬です。",
            "donateScan": "WeChatでスキャン",
        ]),
        Lang(code: "ko", name: "한국어", strings: [
            "backendAuto": "조절:자동", "backendSoftware": "조절:소프트웨어",
            "loginOn": "로그인:켜기", "loginOff": "로그인:끄기",
            "donate": "후원", "quit": "종료", "language": "언어",
            "current": "현재 화면", "hint": "슬립 후 자동 복원",
            "hintGamma": "슬립 후 자동 복원 · 소프트웨어 조절: ",
            "donateLine1": "무료 소프트웨어, 후원은 자유",
            "donateLine2": "도움이 되었다면 그것으로 충분합니다.",
            "donateScan": "WeChat으로 스캔",
        ]),
        Lang(code: "de", name: "Deutsch", strings: [
            "backendAuto": "Dimmung: Auto", "backendSoftware": "Dimmung: SW",
            "loginOn": "Anmeldung: An", "loginOff": "Anmeldung: Aus",
            "donate": "Spenden", "quit": "Beenden", "language": "Sprache",
            "current": "Aktuell", "hint": "Nach Ruhezustand wiederhergestellt",
            "hintGamma": "Nach Ruhezustand wiederhergestellt · Software-Dimmung: ",
            "donateLine1": "Kostenlos, Spende optional",
            "donateLine2": "Wenn es dir hilft, ist das der beste Lohn.",
            "donateScan": "Mit WeChat scannen",
        ]),
        Lang(code: "fr", name: "Français", strings: [
            "backendAuto": "Gradation : Auto", "backendSoftware": "Gradation: Logiciel",
            "loginOn": "Connexion : Oui", "loginOff": "Connexion : Non",
            "donate": "Soutenir", "quit": "Quitter", "language": "Langue",
            "current": "Actuel", "hint": "Restauré après veille",
            "hintGamma": "Restauré après veille · Gradation logicielle : ",
            "donateLine1": "Logiciel gratuit, don facultatif",
            "donateLine2": "Si cela vous aide, c'est ma plus grande récompense.",
            "donateScan": "Scanner avec WeChat",
        ]),
        Lang(code: "es", name: "Español", strings: [
            "backendAuto": "Atenuar: Auto", "backendSoftware": "Atenuar: SW",
            "loginOn": "Inicio: Sí", "loginOff": "Inicio: No",
            "donate": "Apoyar", "quit": "Salir", "language": "Idioma",
            "current": "Actual", "hint": "Restaurado tras suspensión",
            "hintGamma": "Restaurado tras suspensión · Atenuación por software: ",
            "donateLine1": "Software gratuito, donativo opcional",
            "donateLine2": "Si te ayuda, esa es mi mayor recompensa.",
            "donateScan": "Escanear con WeChat",
        ]),
        Lang(code: "it", name: "Italiano", strings: [
            "backendAuto": "Attenua: Auto", "backendSoftware": "Attenua: SW",
            "loginOn": "Login: Sì", "loginOff": "Login: No",
            "donate": "Sostieni", "quit": "Esci", "language": "Lingua",
            "current": "Attuale", "hint": "Ripristinato dopo la sospensione",
            "hintGamma": "Ripristinato dopo la sospensione · Attenuazione software: ",
            "donateLine1": "Software gratuito, offerta facoltativa",
            "donateLine2": "Se ti è utile, è la mia migliore ricompensa.",
            "donateScan": "Scansiona con WeChat",
        ]),
        Lang(code: "pt", name: "Português", strings: [
            "backendAuto": "Atenuar: Auto", "backendSoftware": "Atenuar: SW",
            "loginOn": "Início: Sim", "loginOff": "Início: Não",
            "donate": "Apoiar", "quit": "Sair", "language": "Idioma",
            "current": "Atual", "hint": "Restaurado após suspensão",
            "hintGamma": "Restaurado após suspensão · Atenuação por software: ",
            "donateLine1": "Software gratuito, doação opcional",
            "donateLine2": "Se te ajuda, essa é a maior recompensa.",
            "donateScan": "Digitalizar com WeChat",
        ]),
        Lang(code: "ru", name: "Русский", strings: [
            "backendAuto": "Затемнение: авто", "backendSoftware": "Затемн: прогр",
            "loginOn": "Автозапуск: вкл", "loginOff": "Автозапуск: выкл",
            "donate": "Поддержать", "quit": "Выход", "language": "Язык",
            "current": "Текущий", "hint": "Восстанавливается после сна",
            "hintGamma": "Восстанавливается после сна · Программное затемнение: ",
            "donateLine1": "Программа бесплатна, поддержка по желанию",
            "donateLine2": "Если это помогает — лучшей награды не нужно.",
            "donateScan": "Сканируйте в WeChat",
        ]),
        Lang(code: "vi", name: "Tiếng Việt", strings: [
            "backendAuto": "Giảm sáng: Tự động", "backendSoftware": "Giảm sáng: PM",
            "loginOn": "Khởi động: Bật", "loginOff": "Khởi động: Tắt",
            "donate": "Ủng hộ", "quit": "Thoát", "language": "Ngôn ngữ",
            "current": "Hiện tại", "hint": "Tự khôi phục sau khi ngủ",
            "hintGamma": "Tự khôi phục sau khi ngủ · Giảm sáng bằng phần mềm: ",
            "donateLine1": "Phần mềm miễn phí, ủng hộ tùy ý",
            "donateLine2": "Nếu nó giúp ích cho bạn, đó là phần thưởng lớn nhất.",
            "donateScan": "Quét bằng WeChat",
        ]),
    ]

    private static let key = "appLanguage"

    static var code: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: key),
               languages.contains(where: { $0.code == saved }) {
                return saved
            }
            for preferred in Locale.preferredLanguages {
                if preferred.hasPrefix("zh") {
                    return (preferred.contains("Hant") || preferred.contains("TW") || preferred.contains("HK"))
                        ? "zh-Hant" : "zh-Hans"
                }
                if let base = preferred.split(separator: "-").first,
                   let hit = languages.first(where: { $0.code == String(base) }) {
                    return hit.code
                }
            }
            return "en"
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func t(_ k: String) -> String {
        let lang = languages.first(where: { $0.code == code }) ?? languages[2]
        return lang.strings[k] ?? languages[2].strings[k] ?? k
    }
}
