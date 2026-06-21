import SwiftUI

/// In-app emoji panel for the chat composer. Pure client-side — picked emoji
/// are appended to the text field and ride the normal text-message send, so
/// nothing here touches the network or message model. "Recent" is persisted
/// locally. Categories cover the common Apple emoji groups.
struct ChatEmojiPanel: View {
    @Environment(\.appLanguage) private var language
    let onPick: (String) -> Void

    @AppStorage("chat.recentEmoji.v1") private var recentRaw = ""
    @State private var category = 0

    private var recent: [String] {
        recentRaw.split(separator: " ").map(String.init)
    }

    private struct Category { let title: (zh: String, ja: String, en: String); let icon: String; let emojis: [String] }

    private static let categories: [Category] = [
        Category(title: ("笑脸", "笑顔", "Smileys"), icon: "😀", emojis: ["😀","😃","😄","😁","😆","😅","😂","🤣","🥲","☺️","😊","😇","🙂","🙃","😉","😌","😍","🥰","😘","😗","😙","😚","😋","😛","😝","😜","🤪","🤨","🧐","🤓","😎","🥳","😏","😒","😞","😔","😟","😕","🙁","☹️","😣","😖","😫","😩","🥺","😢","😭","😤","😠","😡","🤬","🤯","😳","🥵","🥶","😱","😨","😰","😥","😓","🤗","🤔","🤭","🤫","🤥","😶","😐","😑","😬","🙄","😯","😦","😧","😮","😲","🥱","😴","🤤","😪","🤐","🥴","🤢","🤮","🤧","😷","🤒","🤕","🤑","🤠"]),
        Category(title: ("手势", "ジェスチャー", "Gestures"), icon: "👍", emojis: ["👍","👎","👊","✊","🤛","🤜","👏","🙌","👐","🤲","🙏","🤝","💪","🦾","✌️","🤞","🫰","🤟","🤘","🤙","👈","👉","👆","🖕","👇","☝️","👌","🤌","🤏","✋","🤚","🖐️","🖖","👋","🫶","🫵","✍️","💅","🤳","💋","👄","👀","👁️","👅","👂","👃","🧠","🫀","🦷","🦴"]),
        Category(title: ("动物", "動物", "Animals"), icon: "🐶", emojis: ["🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐨","🐯","🦁","🐮","🐷","🐸","🐵","🙈","🙉","🙊","🐒","🐔","🐧","🐦","🐤","🦆","🦅","🦉","🦇","🐺","🐗","🐴","🦄","🐝","🪲","🐛","🦋","🐌","🐞","🐜","🐢","🐍","🦎","🐙","🦑","🦀","🦞","🐠","🐟","🐡","🐬","🐳","🐋","🦈","🐊","🐅","🐆","🦓","🦍","🦧","🐘","🦛","🦏","🐪","🐫","🦒","🦘","🐃","🐂","🐄","🐎","🐖","🐏","🐑","🐐","🦌","🐕","🐩","🐈","🐓","🦃","🦚","🦜","🕊️","🐇","🦝","🦡","🐾"]),
        Category(title: ("食物", "食べ物", "Food"), icon: "🍔", emojis: ["🍏","🍎","🍐","🍊","🍋","🍌","🍉","🍇","🍓","🫐","🍈","🍒","🍑","🥭","🍍","🥥","🥝","🍅","🍆","🥑","🥦","🥬","🥒","🌶️","🫑","🌽","🥕","🧄","🧅","🥔","🍠","🥐","🥯","🍞","🥖","🥨","🧀","🥚","🍳","🧈","🥞","🧇","🥓","🥩","🍗","🍖","🌭","🍔","🍟","🍕","🫓","🥪","🌮","🌯","🫔","🥙","🧆","🥘","🍝","🍜","🍲","🍛","🍣","🍱","🥟","🍤","🍙","🍚","🍘","🍥","🥠","🍢","🍡","🍧","🍨","🍦","🥧","🧁","🍰","🎂","🍮","🍭","🍬","🍫","🍿","🍩","🍪","🌰","☕","🍵","🧋","🥤","🧃","🍶","🍺","🍻","🥂","🍷","🥃","🍸","🍹"]),
        Category(title: ("活动", "アクティビティ", "Activity"), icon: "⚽", emojis: ["⚽","🏀","🏈","⚾","🥎","🎾","🏐","🏉","🥏","🎱","🪀","🏓","🏸","🥅","🏒","🏑","🥍","🏏","⛳","🪁","🏹","🎣","🤿","🥊","🥋","🎽","⛸️","🥌","🛷","🎿","⛷️","🏂","🏋️","🤸","🤼","🤽","🤾","🧗","🚴","🚵","🏆","🥇","🥈","🥉","🏅","🎖️","🎮","🕹️","🎯","🎲","🎰","🎳","🎸","🎷","🎺","🎻","🪕","🥁","🎬","🎤","🎧","🎨","🧩"]),
        Category(title: ("旅行", "旅行", "Travel"), icon: "✈️", emojis: ["🚗","🚕","🚙","🚌","🚎","🏎️","🚓","🚑","🚒","🚐","🛻","🚚","🚛","🚜","🛵","🏍️","🛺","🚲","🛴","✈️","🛫","🛬","🚀","🛸","🚁","⛵","🚤","🛥️","🛳️","⚓","🗺️","🗽","🗼","🏰","🏯","🎡","🎢","🎠","⛲","🏖️","🏝️","🏜️","🌋","🗻","⛰️","🏔️","🏕️","⛺","🛖","🏠","🏡","🏙️","🌃","🌆","🌇","🌅","🌄","🌉","🎑","🌁"]),
        Category(title: ("物品", "もの", "Objects"), icon: "💡", emojis: ["⌚","📱","💻","⌨️","🖥️","🖨️","🖱️","💽","💾","💿","📷","📸","🎥","📹","📺","📻","🎙️","⏰","⏱️","⏲️","🔋","🪫","🔌","💡","🔦","🕯️","🧯","💸","💵","💴","💶","💷","🪙","💰","💳","🧾","💎","⚖️","🔧","🔨","🛠️","⚙️","🧰","🧲","💊","💉","🩹","🩺","🧬","🔬","🔭","📡","✏️","✒️","🖊️","🖋️","📝","📚","📖","📰","📅","📌","📎","🔑","🗝️","🔒","🔓","🎁","🎈","🎉","🎊","🧧","🛍️","🎒"]),
        Category(title: ("符号", "記号", "Symbols"), icon: "❤️", emojis: ["❤️","🧡","💛","💚","💙","💜","🖤","🤍","🤎","💔","❣️","💕","💞","💓","💗","💖","💘","💝","💟","✨","⭐","🌟","💫","⚡","🔥","💥","💯","💢","💦","💨","✅","☑️","✔️","❌","⭕","❓","❗","❕","💤","🎵","🎶","➕","➖","➗","🟰","🆗","🆕","🔝","🉑","㊗️","🈵","🚫","⚠️","♻️","🔘","🔴","🟠","🟡","🟢","🔵","🟣","⚫","⚪","🟥","🟧","🟨","🟩","🟦","🟪"]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !recent.isEmpty {
                Text(language == .ja ? "最近" : language == .en ? "Recent" : "最近使用")
                    .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    .padding(.leading, 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recent, id: \.self) { e in emojiButton(e) }
                    }
                    .padding(.horizontal, 4)
                }
            }

            HStack(spacing: 4) {
                ForEach(Array(Self.categories.enumerated()), id: \.offset) { index, cat in
                    Button {
                        withAnimation(.snappy(duration: 0.15)) { category = index }
                    } label: {
                        Text(cat.icon)
                            .font(.title3)
                            .frame(width: 34, height: 30)
                            .background(category == index ? KXColor.accent.opacity(0.14) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pick(cat.title))
                }
                Spacer(minLength: 0)
            }

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 8), spacing: 6) {
                    ForEach(Self.categories[category].emojis, id: \.self) { e in emojiButton(e) }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 196)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(KXColor.cardBackground.opacity(0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator.opacity(0.24), lineWidth: 0.7))
    }

    private func emojiButton(_ e: String) -> some View {
        Button { tap(e) } label: {
            Text(e).font(.system(size: 30)).frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }

    private func tap(_ e: String) {
        onPick(e)
        var list = recent.filter { $0 != e }
        list.insert(e, at: 0)
        recentRaw = list.prefix(24).joined(separator: " ")
    }

    private func pick(_ t: (zh: String, ja: String, en: String)) -> String {
        language == .ja ? t.ja : language == .en ? t.en : t.zh
    }
}
