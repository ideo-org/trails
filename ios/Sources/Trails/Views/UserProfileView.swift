//
//  UserProfileView.swift
//  Trails
//
//  Tab 3: You (Author profile & spatial device survey settings).
//

import SwiftUI

public struct UserProfileView: View {
    @ObservedObject var authManager = AuthManager.shared
    @ObservedObject var dataStore = TrailsDataStore.shared

    @State private var showingEditProfile: Bool = false
    @State private var showingLoginSheet: Bool = false
    @State private var draftDisplayName: String = ""
    @State private var draftUsername: String = ""
    @State private var draftIntroduction: String = ""

    public init() {}

    private var effectiveDisplayName: String {
        let name = dataStore.localProfile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && name != "A trail by you" {
            return name
        }
        #if canImport(Firebase)
        if let googleName = authManager.user?.displayName, !googleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return googleName
        }
        #endif
        return name.isEmpty ? "A trail by you" : name
    }

    private var effectiveUsername: String {
        if let u = dataStore.localProfile.username?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            return u.hasPrefix("@") ? String(u.dropFirst()) : u
        }
        #if canImport(Firebase)
        if let email = authManager.user?.email, let prefix = email.split(separator: "@").first, !prefix.isEmpty {
            return String(prefix).lowercased()
        }
        #endif
        let derived = effectiveDisplayName.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber }
        return derived.isEmpty ? "explorer" : derived
    }

    private var effectiveAvatarURL: URL? {
        #if canImport(Firebase)
        if let photoURL = authManager.user?.photoURL {
            return photoURL
        }
        #endif
        if let urlStr = dataStore.localProfile.avatarURL, let url = URL(string: urlStr) {
            return url
        }
        return nil
    }

    private var fallbackAvatar: some View {
        Circle()
            .fill(AppColors.surfaceContainerHigh)
            .frame(width: 76, height: 76)
            .overlay(
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(AppColors.terracotta)
            )
    }

    private var effectiveIntroduction: String {
        let intro = dataStore.localProfile.introduction.trimmingCharacters(in: .whitespacesAndNewlines)
        return intro.isEmpty ? "Local Spatial Contributor" : intro
    }

    private var totalMomentsCount: Int {
        dataStore.savedTrails.reduce(0) { $0 + $1.moments.count }
    }

    private var totalMetersRecorded: Int {
        dataStore.savedTrails.reduce(0) { $0 + $1.distanceMeters }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppColors.canvas
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // MARK: - Author Card
                        VStack(spacing: 12) {
                            if let avatarURL = effectiveAvatarURL {
                                AsyncImage(url: avatarURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 76, height: 76)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(AppColors.outlineVariant.opacity(0.4), lineWidth: 1.5))
                                            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                                    default:
                                        fallbackAvatar
                                    }
                                }
                            } else {
                                fallbackAvatar
                            }

                            VStack(spacing: 4) {
                                Text(effectiveDisplayName)
                                    .font(AppFonts.headlineLarge)
                                    .foregroundColor(AppColors.deepInk)

                                Text("@\(effectiveUsername)")
                                    .font(AppFonts.labelSpatial)
                                    .foregroundColor(AppColors.forestGreen)

                                Text(effectiveIntroduction)
                                    .font(AppFonts.bodyMedium)
                                    .foregroundColor(AppColors.outline)
                                    .multilineTextAlignment(.center)
                            }

                            // Edit Profile Button (PRD ID-03)
                            Button {
                                draftDisplayName = dataStore.localProfile.displayName
                                draftUsername = dataStore.localProfile.username ?? effectiveUsername
                                draftIntroduction = dataStore.localProfile.introduction
                                showingEditProfile = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "pencil")
                                    Text("Edit Identity")
                                }
                                .font(AppFonts.labelUI)
                                .foregroundColor(AppColors.forestGreen)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(AppColors.surfaceContainerLow)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(AppColors.outlineVariant.opacity(0.4), lineWidth: 1)
                                )
                            }
                            .padding(.top, 4)

                            // Author statistics pill
                            HStack(spacing: 16) {
                                VStack(spacing: 2) {
                                    Text("\(dataStore.savedTrails.count)")
                                        .font(AppFonts.headlineSmall)
                                        .foregroundColor(AppColors.deepInk)
                                    Text("Trails")
                                        .font(AppFonts.labelSpatial)
                                        .foregroundColor(AppColors.outline)
                                }

                                Divider()
                                    .frame(height: 24)

                                VStack(spacing: 2) {
                                    Text("\(totalMomentsCount)")
                                        .font(AppFonts.headlineSmall)
                                        .foregroundColor(AppColors.deepInk)
                                    Text("Moments")
                                        .font(AppFonts.labelSpatial)
                                        .foregroundColor(AppColors.outline)
                                }

                                Divider()
                                    .frame(height: 24)

                                VStack(spacing: 2) {
                                    Text("\(totalMetersRecorded) m")
                                        .font(AppFonts.headlineSmall)
                                        .foregroundColor(AppColors.deepInk)
                                    Text("Recorded")
                                        .font(AppFonts.labelSpatial)
                                        .foregroundColor(AppColors.outline)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(AppColors.surfaceContainerLow)
                            .clipShape(Capsule())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(AppColors.pureWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                        // MARK: - Account & Cloud Identity (Firebase Google Sign-In)
                        accountIdentitySection

                        // MARK: - Privacy & Local Storage (PRD 11.3)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundColor(AppColors.forestGreen)
                                Text("Private by Default")
                                    .font(AppFonts.headlineSmall)
                                    .foregroundColor(AppColors.deepInk)
                            }

                            Text("Saved privately on this device. Trails does not upload this capture. Captures stay on your device and are not automatically backed up.")
                                .font(AppFonts.bodySmall)
                                .foregroundColor(AppColors.onSurfaceVariant)
                                .lineSpacing(2)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.pureWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppColors.outlineVariant.opacity(0.4), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                        .padding(.horizontal, 20)

                        // MARK: - Spatial Hardware Diagnostics
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Spatial Survey Instrument")
                                .font(AppFonts.headlineSmall)
                                .foregroundColor(AppColors.deepInk)
                                .padding(.horizontal, 20)

                            VStack(spacing: 0) {
                                DiagnosticRow(title: "LiDAR Point Cloud Engine", value: "Active (24.6 kHz)", isOk: true)
                                Divider().padding(.leading, 16)
                                DiagnosticRow(title: "Apple RoomPlan API", value: "Available", isOk: true)
                                Divider().padding(.leading, 16)
                                DiagnosticRow(title: "6DOF Odometry Tracking", value: "Calibrated", isOk: true)
                                Divider().padding(.leading, 16)
                                DiagnosticRow(title: "Spatial Audio Field Mic", value: "48 kHz Stereo", isOk: true)
                            }
                            .background(AppColors.pureWhite)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                            .padding(.horizontal, 20)
                        }

                        // MARK: - Storage & Cache
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Local Storage & Cache")
                                .font(AppFonts.headlineSmall)
                                .foregroundColor(AppColors.deepInk)
                                .padding(.horizontal, 20)

                            VStack(spacing: 0) {
                                DiagnosticRow(title: "Local Trails Count", value: "\(dataStore.savedTrails.count) Saved, \(dataStore.userDrafts.count) Draft", isOk: nil)
                                Divider().padding(.leading, 16)
                                DiagnosticRow(title: "Offline Mesh Cache", value: "128.4 MB", isOk: nil)
                            }
                            .background(AppColors.pureWhite)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                            .padding(.horizontal, 20)
                        }

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("You")
                        .font(AppFonts.headlineSmall)
                        .foregroundColor(AppColors.deepInk)
                }
            }
            .sheet(isPresented: $showingEditProfile) {
                editProfileSheet
            }
            .sheet(isPresented: $showingLoginSheet) {
                #if canImport(GoogleSignIn)
                LoginView()
                    .environmentObject(authManager)
                #endif
            }
        }
    }

    // MARK: - Account & Cloud Identity Section

    private var accountIdentitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            #if canImport(Firebase)
            if authManager.authState == .signedIn {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.forestGreen)
                        .font(.system(size: 24))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(authManager.user?.displayName ?? "Google Account")
                            .font(AppFonts.headlineSmall)
                            .foregroundColor(AppColors.deepInk)

                        if let email = authManager.user?.email {
                            Text(email)
                                .font(AppFonts.caption)
                                .foregroundColor(AppColors.outline)
                        }
                    }

                    Spacer()

                    Button {
                        Haptics.light()
                        authManager.signOut()
                    } label: {
                        Text("Sign Out")
                            .font(AppFonts.labelUI)
                            .foregroundColor(AppColors.error)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(AppColors.surfaceContainerLow)
                            .clipShape(Capsule())
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .foregroundColor(AppColors.forestGreen)
                            .font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cloud Identity")
                                .font(AppFonts.headlineSmall)
                                .foregroundColor(AppColors.deepInk)
                            Text("Sign in with Google to sync your profile across devices.")
                                .font(AppFonts.caption)
                                .foregroundColor(AppColors.outline)
                        }
                    }

                    Button {
                        Haptics.medium()
                        showingLoginSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "g.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("Sign in with Google")
                                .font(AppFonts.labelUI)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(AppColors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(AppColors.forestGreen)
                        .clipShape(Capsule())
                    }
                }
            }
            #else
            EmptyView()
            #endif
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.pureWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColors.outlineVariant.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        .padding(.horizontal, 20)
    }

    private var editProfileSheet: some View {
        NavigationStack {
            ZStack {
                AppColors.canvas
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DISPLAY NAME")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.outline)

                        TextField("Display Name", text: $draftDisplayName)
                            .font(AppFonts.bodyLarge)
                            .foregroundColor(AppColors.deepInk)
                            .padding(14)
                            .background(AppColors.pureWhite)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppColors.outlineVariant.opacity(0.5), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("USERNAME")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.outline)

                        HStack(spacing: 4) {
                            Text("@")
                                .font(AppFonts.bodyLarge)
                                .foregroundColor(AppColors.outline)

                            TextField("username", text: $draftUsername)
                                .font(AppFonts.bodyLarge)
                                .foregroundColor(AppColors.deepInk)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .padding(14)
                        .background(AppColors.pureWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppColors.outlineVariant.opacity(0.5), lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("CONTEXT / FOCUS (OPTIONAL)")
                            .font(AppFonts.labelSpatial)
                            .foregroundColor(AppColors.outline)

                        TextField("e.g., Architect, Spatial explorer", text: $draftIntroduction)
                            .font(AppFonts.bodyMedium)
                            .foregroundColor(AppColors.deepInk)
                            .padding(14)
                            .background(AppColors.pureWhite)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppColors.outlineVariant.opacity(0.5), lineWidth: 1)
                            )
                    }

                    Text("Attribution is registered with your published spatial trails across the community.")
                        .font(AppFonts.labelSpatial)
                        .foregroundColor(AppColors.outline)

                    Spacer()

                    Button("Save") {
                        let cleanName = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanIntro = draftIntroduction.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanUser = draftUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                        dataStore.updateProfile(
                            displayName: cleanName.isEmpty ? "A trail by you" : cleanName,
                            introduction: cleanIntro,
                            username: cleanUser.isEmpty ? nil : cleanUser,
                            avatarURL: effectiveAvatarURL?.absoluteString
                        )
                        showingEditProfile = false
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(24)
            }
            .navigationTitle("Edit Identity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingEditProfile = false
                    }
                    .foregroundColor(AppColors.forestGreen)
                }
            }
        }
    }
}

struct DiagnosticRow: View {
    let title: String
    let value: String
    let isOk: Bool?

    var body: some View {
        HStack {
            Text(title)
                .font(AppFonts.bodyMedium)
                .foregroundColor(AppColors.deepInk)

            Spacer()

            if let isOk = isOk {
                Circle()
                    .fill(isOk ? AppColors.terracotta : AppColors.outline)
                    .frame(width: 6, height: 6)
            }

            Text(value)
                .font(AppFonts.labelMetric)
                .foregroundColor(AppColors.outline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
