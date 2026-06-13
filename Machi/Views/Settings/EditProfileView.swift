import SwiftData
import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var displayName: String
    @State private var bio: String
    @State private var location: String
    @State private var avatarURL: String
    @State private var coverURL: String
    @State private var avatarSymbol: String
    @State private var avatarColorName: String
    @State private var avatarItem: PhotosPickerItem?
    @State private var coverItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var isPreparingMedia = false
    @State private var errorMessage: String?

    let user: UserEntity

    init(user: UserEntity) {
        self.user = user
        _displayName = State(initialValue: user.displayName)
        _bio = State(initialValue: user.bio)
        _location = State(initialValue: user.location)
        _avatarURL = State(initialValue: user.avatarURL)
        _coverURL = State(initialValue: user.coverURL)
        _avatarSymbol = State(initialValue: user.avatarSymbol)
        _avatarColorName = State(initialValue: user.avatarColorName)
    }

    private var canSave: Bool {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && isSaving == false && isPreparingMedia == false
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    editHeaderPreview

                    formCard

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, 14)
                .kxTabBarSafeBottomPadding()
            }
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: avatarItem) { _, item in
            Task { await preparePickedImage(item, target: .avatar) }
        }
        .onChange(of: coverItem) { _, item in
            Task { await preparePickedImage(item, target: .cover) }
        }
    }

    private var header: some View {
        HStack {
            Button(L("cancel", language)) {
                dismiss()
            }
            .font(.headline.weight(.bold))
            .foregroundStyle(.primary)

            Spacer()

            Text(L("editProfile", language))
                .font(.headline.weight(.semibold))

            Spacer()

            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    KXSpinner(size: 22, lineWidth: 2.4)
                } else {
                    Text(L("save", language))
                        .font(.headline.weight(.semibold))
                }
            }
            .foregroundStyle(canSave ? KXColor.accent : .secondary)
            .frame(width: 62, height: 36)
            .kxGlassCapsule(isSelected: canSave)
            .disabled(!canSave)
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }

    private var editHeaderPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                coverPreview
                    .frame(height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: KXRadius.lg))

                avatarPreview(size: 74)
                    .overlay(Circle().stroke(Color(.systemBackground).opacity(0.82), lineWidth: 5))
                    .offset(x: 16, y: 34)
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text(displayName.isEmpty ? user.displayName : displayName)
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)
                        if user.displaysVerifiedBadge {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    Text("@\(user.username)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isPreparingMedia {
                    KXSpinner(size: 22, lineWidth: 2.4)
                }
            }
            .padding(.top, 42)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            mediaPickers
            Divider().opacity(0.5)
            labeledField(title: L("displayName", language), text: $displayName, axis: .horizontal)
            Divider().opacity(0.5)
            labeledField(title: L("bio", language), text: $bio, axis: .vertical)
            Divider().opacity(0.5)
            labeledField(title: L("location", language), text: $location, axis: .horizontal)
            Divider().opacity(0.5)
            avatarStylePicker
        }
        .padding(18)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private var avatarStylePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("avatarStyle", language))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(["sparkles", "star.fill", "person.fill", "newspaper.fill", "tram.fill", "fork.knife", "camera.fill", "bolt.fill"], id: \.self) { symbol in
                    Button {
                        avatarSymbol = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(avatarSymbol == symbol ? .white : .primary)
                            .frame(width: 38, height: 38)
                            .background(avatarSymbol == symbol ? KXColor.accent.opacity(0.78) : KXColor.glassControlTint)
                            .kxLiquidGlass(avatarSymbol == symbol ? .selected : .control, in: Circle())
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            FlowLayout(spacing: 8) {
                ForEach(["pink", "orange", "blue", "green", "purple", "teal", "red", "black"], id: \.self) { colorName in
                    Button {
                        avatarColorName = colorName
                    } label: {
                        Circle()
                            .fill(Color.kaixNamed(colorName).gradient)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle().stroke(avatarColorName == colorName ? Color.primary : Color.clear, lineWidth: 3)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var mediaPickers: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("avatarAndCover", language))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    Label(L("chooseAvatar", language), systemImage: "person.crop.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .kxGlassCapsule()
                }
                .disabled(isPreparingMedia)

                PhotosPicker(selection: $coverItem, matching: .images) {
                    Label(L("chooseCover", language), systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .kxGlassCapsule()
                }
                .disabled(isPreparingMedia)
            }
        }
    }

    @ViewBuilder
    private var coverPreview: some View {
        if let url = coverURL.kaixMediaURL {
            CachedMediaImageView(url: url, targetPixelSize: 900)
        } else {
            LinearGradient(
                colors: [Color.pink.opacity(0.86), Color.blue.opacity(0.28), Color.gray.opacity(0.36)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func avatarPreview(size: CGFloat) -> some View {
        ZStack {
            if let url = avatarURL.kaixMediaURL {
                CachedMediaImageView(url: url, targetPixelSize: size * 3)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.kaixNamed(avatarColorName).gradient)
                Image(systemName: avatarSymbol)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func labeledField(title: String, text: Binding<String>, axis: Axis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)

            TextField(title, text: text, axis: axis)
                .font(.body)
                .lineLimit(axis == .vertical ? 3...6 : 1...1)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .kxGlassSurface(radius: KXRadius.md)
        }
    }

    @MainActor
    private func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        do {
            try await UserRepository(context: modelContext).updateProfile(
                user: user,
                displayName: displayName,
                bio: bio,
                location: location
            )
            user.avatarURL = avatarURL
            user.coverURL = coverURL
            user.avatarSymbol = avatarSymbol
            user.avatarColorName = avatarColorName
            user.updatedAt = .now
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.kaixUserMessage
        }
        isSaving = false
    }

    @MainActor
    private func preparePickedImage(_ item: PhotosPickerItem?, target: PickedProfileImageTarget) async {
        guard let item else { return }
        isPreparingMedia = true
        errorMessage = nil
        defer { isPreparingMedia = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw UploadService.UploadError.invalidMedia
            }
            let draft = try await UploadService.shared.prepareImage(data: data)
            switch target {
            case .avatar:
                avatarURL = draft.thumbnailURL.path
            case .cover:
                coverURL = draft.localURL.path
            }
        } catch {
            errorMessage = L("mediaFailed", language)
        }
    }
}

private enum PickedProfileImageTarget {
    case avatar
    case cover
}
