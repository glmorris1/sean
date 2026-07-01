import SwiftUI

@main
struct SeanApp: App {
    @State private var auth = AuthService()

    var body: some Scene {
        WindowGroup {
            AuthGateView(auth: auth)
        }
    }
}

private struct AuthGateView: View {
    @Bindable var auth: AuthService

    var body: some View {
        Group {
            if auth.isSignedIn {
                ContentView(auth: auth)
            } else if auth.pendingVerificationEmail != nil {
                EmailVerificationView(auth: auth)
            } else {
                LoginView(auth: auth)
            }
        }
    }
}

private struct LoginView: View {
    @Bindable var auth: AuthService
    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var rememberUser = true
    @FocusState private var focusedField: LoginField?

    private enum LoginField {
        case email
        case password
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 18)

                VStack(spacing: 8) {
                    Image("LoginIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                        .padding(.bottom, 6)
                    Text("GhostTrade")
                        .font(.system(size: 44, weight: .black))
                        .foregroundStyle(.black)
                    Text("Sign in to sync watchlists, paper trading, and backtesting across devices.")
                        .font(.subheadline)
                        .foregroundStyle(.black.opacity(0.64))
                        .multilineTextAlignment(.center)
                }

                Picker("Mode", selection: $mode) {
                    Text("Sign In").tag(AuthMode.signIn)
                    Text("Create Account").tag(AuthMode.signUp)
                }
                .pickerStyle(.segmented)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .authFieldStyle()
                        .onSubmit {
                            focusedField = .password
                        }

                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.done)
                        .authFieldStyle()
                        .onSubmit {
                            focusedField = nil
                        }
                }

                if mode == .signIn {
                    Toggle(isOn: $rememberUser) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remember me")
                                .font(.subheadline.bold())
                                .foregroundStyle(.black)
                            Text("Use this account for Face ID login on this device.")
                                .font(.caption)
                                .foregroundStyle(.black.opacity(0.58))
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(.blue)
                }

                if let error = auth.errorMessage {
                    Text(error)
                        .font(.footnote.bold())
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task {
                        switch mode {
                        case .signIn:
                            await auth.signIn(email: email, password: password, rememberUser: rememberUser)
                        case .signUp:
                            await auth.signUp(email: email, password: password)
                        }
                    }
                } label: {
                    Text(mode == .signIn ? "Sign In" : "Create Account")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(auth.isLoading)

                Button {
                    Task { await auth.signInWithGoogle(rememberUser: rememberUser) }
                } label: {
                    HStack(spacing: 12) {
                        GoogleGMark()
                            .frame(width: 22, height: 22)
                        Text("Continue with Google")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.84))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black.opacity(0.16), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(auth.isLoading)

                if auth.canUseFaceID {
                    Button {
                        Task { await auth.unlockWithFaceID() }
                    } label: {
                        VStack(spacing: 4) {
                            Label("Login with Face ID", systemImage: "faceid")
                                .font(.headline)
                            if let rememberedEmail = auth.rememberedEmail {
                                Text(rememberedEmail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(auth.isLoading)
                }

                Spacer()
            }
            .padding(24)
            .background(Color(uiColor: .systemGroupedBackground))
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
            }
            .preferredColorScheme(.light)
            .tint(.blue)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        focusedField = nil
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .accessibilityLabel("Collapse keyboard")
                }
            }
        }
    }
}

private struct GoogleGMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            context.translateBy(
                x: (size.width - 24 * scale) / 2,
                y: (size.height - 24 * scale) / 2
            )
            context.scaleBy(x: scale, y: scale)

            context.fill(googleBluePath, with: .color(Color(red: 0.259, green: 0.522, blue: 0.957)))
            context.fill(googleGreenPath, with: .color(Color(red: 0.204, green: 0.659, blue: 0.325)))
            context.fill(googleYellowPath, with: .color(Color(red: 0.984, green: 0.737, blue: 0.020)))
            context.fill(googleRedPath, with: .color(Color(red: 0.918, green: 0.263, blue: 0.208)))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var googleBluePath: Path {
        Path { path in
            path.move(to: CGPoint(x: 23.49, y: 12.27))
            path.addCurve(to: CGPoint(x: 23.30, y: 10.00), control1: CGPoint(x: 23.49, y: 11.48), control2: CGPoint(x: 23.42, y: 10.73))
            path.addLine(to: CGPoint(x: 12.00, y: 10.00))
            path.addLine(to: CGPoint(x: 12.00, y: 14.51))
            path.addLine(to: CGPoint(x: 18.47, y: 14.51))
            path.addCurve(to: CGPoint(x: 16.06, y: 18.02), control1: CGPoint(x: 18.19, y: 15.96), control2: CGPoint(x: 17.34, y: 17.19))
            path.addLine(to: CGPoint(x: 16.06, y: 20.93))
            path.addLine(to: CGPoint(x: 19.95, y: 20.93))
            path.addCurve(to: CGPoint(x: 23.49, y: 12.27), control1: CGPoint(x: 22.23, y: 18.83), control2: CGPoint(x: 23.49, y: 15.75))
            path.closeSubpath()
        }
    }

    private var googleGreenPath: Path {
        Path { path in
            path.move(to: CGPoint(x: 12.00, y: 24.00))
            path.addCurve(to: CGPoint(x: 19.93, y: 21.09), control1: CGPoint(x: 15.24, y: 24.00), control2: CGPoint(x: 17.95, y: 22.93))
            path.addLine(to: CGPoint(x: 16.04, y: 18.18))
            path.addCurve(to: CGPoint(x: 12.00, y: 19.33), control1: CGPoint(x: 14.96, y: 18.90), control2: CGPoint(x: 13.59, y: 19.33))
            path.addCurve(to: CGPoint(x: 5.33, y: 14.43), control1: CGPoint(x: 8.90, y: 19.33), control2: CGPoint(x: 6.27, y: 17.24))
            path.addLine(to: CGPoint(x: 1.29, y: 17.44))
            path.addCurve(to: CGPoint(x: 12.00, y: 24.00), control1: CGPoint(x: 3.26, y: 21.36), control2: CGPoint(x: 7.34, y: 24.00))
            path.closeSubpath()
        }
    }

    private var googleYellowPath: Path {
        Path { path in
            path.move(to: CGPoint(x: 5.33, y: 14.43))
            path.addCurve(to: CGPoint(x: 4.94, y: 12.00), control1: CGPoint(x: 5.08, y: 13.71), control2: CGPoint(x: 4.94, y: 12.94))
            path.addCurve(to: CGPoint(x: 5.33, y: 9.57), control1: CGPoint(x: 4.94, y: 11.06), control2: CGPoint(x: 5.08, y: 10.29))
            path.addLine(to: CGPoint(x: 5.33, y: 6.56))
            path.addLine(to: CGPoint(x: 1.29, y: 6.56))
            path.addCurve(to: CGPoint(x: 0.00, y: 12.00), control1: CGPoint(x: 0.47, y: 8.19), control2: CGPoint(x: 0.00, y: 10.04))
            path.addCurve(to: CGPoint(x: 1.29, y: 17.44), control1: CGPoint(x: 0.00, y: 13.96), control2: CGPoint(x: 0.47, y: 15.81))
            path.addLine(to: CGPoint(x: 5.33, y: 14.43))
            path.closeSubpath()
        }
    }

    private var googleRedPath: Path {
        Path { path in
            path.move(to: CGPoint(x: 12.00, y: 4.67))
            path.addCurve(to: CGPoint(x: 16.60, y: 6.47), control1: CGPoint(x: 13.77, y: 4.67), control2: CGPoint(x: 15.35, y: 5.28))
            path.addLine(to: CGPoint(x: 20.02, y: 3.05))
            path.addCurve(to: CGPoint(x: 12.00, y: 0.00), control1: CGPoint(x: 17.95, y: 1.13), control2: CGPoint(x: 15.24, y: 0.00))
            path.addCurve(to: CGPoint(x: 1.29, y: 6.56), control1: CGPoint(x: 7.34, y: 0.00), control2: CGPoint(x: 3.26, y: 2.64))
            path.addLine(to: CGPoint(x: 5.33, y: 9.57))
            path.addCurve(to: CGPoint(x: 12.00, y: 4.67), control1: CGPoint(x: 6.27, y: 6.76), control2: CGPoint(x: 8.90, y: 4.67))
            path.closeSubpath()
        }
    }
}

private struct EmailVerificationView: View {
    @Bindable var auth: AuthService
    @State private var code = ""
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer(minLength: 24)
                Image(systemName: auth.isUsingLocalDevelopmentVerification ? "number.circle.fill" : "envelope.badge.shield.half.filled")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.blue)
                Text(auth.isUsingLocalDevelopmentVerification ? "Development Verification" : "Verify Your Email")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.black)
                Text(verificationMessage)
                    .font(.subheadline)
                    .foregroundStyle(.black.opacity(0.64))
                    .multilineTextAlignment(.center)

                if auth.verificationRequiresCode {
                    TextField("Verification code", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($isCodeFocused)
                        .authFieldStyle()
                        .multilineTextAlignment(.center)
                }

                if let developmentCode = auth.lastDevelopmentVerificationCode {
                    Text(developmentCode)
                        .font(.system(size: 28, weight: .black, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.blue.opacity(0.28), lineWidth: 1)
                        }
                }

                if let error = auth.errorMessage {
                    Text(error)
                        .font(.footnote.bold())
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await auth.verifyEmail(code: code) }
                } label: {
                    Text(auth.verificationRequiresCode ? "Verify Email" : "I've Verified")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(auth.verificationRequiresCode ? "Resend Code" : "Resend Email") {
                    Task { await auth.resendVerification() }
                }
                .disabled(auth.isLoading)

                Button("Back to Sign In") {
                    auth.cancelPendingVerification()
                }
                .font(.footnote.bold())

                Spacer()
            }
            .padding(24)
            .background(Color(uiColor: .systemGroupedBackground))
            .contentShape(Rectangle())
            .onTapGesture {
                isCodeFocused = false
            }
            .preferredColorScheme(.light)
            .tint(.blue)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        isCodeFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .accessibilityLabel("Collapse keyboard")
                }
            }
        }
    }

    private var verificationMessage: String {
        if auth.isUsingLocalDevelopmentVerification {
            return "Use the temporary code below to finish creating this local test account."
        }
        if auth.verificationRequiresCode {
            return "Enter the verification code sent to \(auth.pendingVerificationEmail ?? "your email")."
        }
        return "Firebase sent a verification link to \(auth.pendingVerificationEmail ?? "your email"). Tap that link, then return to GhostTrade and tap I've Verified."
    }
}

private extension View {
    func authFieldStyle() -> some View {
        self
            .font(.body)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.black.opacity(0.08), lineWidth: 1)
            }
    }
}
