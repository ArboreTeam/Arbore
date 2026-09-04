import CoreLocation
import SwiftUI
import UIKit

/// Récupère une localisation fraîche après chaque scan. Même si l'autorisation
/// système existe déjà, l'utilisateur choisit explicitement la position de ce
/// nouveau jardin afin de couvrir le cas d'une résidence secondaire.
struct GardenLocationCaptureView: View {
    let onReady: (GardenLocationDTO) -> Void
    let onSkip: () -> Void

    @StateObject private var controller = FreshGardenLocationController()
    @State private var mode: Mode = .choice
    @State private var manualCity = ""
    @State private var isRequestingLocation = false
    @State private var didComplete = false
    @FocusState private var cityFieldFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    private enum Mode: Equatable {
        case choice
        case locating
        case manualCity
    }

    var body: some View {
        ZStack {
            Color.gardenBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(ArboreDesign.Colors.softGreenBackground)
                        .frame(width: 112, height: 112)

                    Image(systemName: "location.fill")
                        .font(.system(size: 43, weight: .semibold))
                        .foregroundColor(ArboreDesign.Colors.primaryGreen)
                }

                Text(L10n.t("GARDEN_LOCATION_EYEBROW").uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.1)
                    .foregroundColor(ArboreDesign.Colors.primaryGreen)
                    .padding(.top, 26)

                Text(title)
                    .font(.system(size: 29, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Text(description)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                if mode == .manualCity {
                    TextField(L10n.t("GARDEN_LOCATION_CITY_PLACEHOLDER"), text: $manualCity)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.continue)
                        .focused($cityFieldFocused)
                        .onSubmit(saveManualCity)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(
                            ArboreDesign.Colors.softSurface,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
                        )
                        .padding(.top, 22)
                } else {
                    Label(
                        L10n.t("GARDEN_LOCATION_PRIVACY"),
                        systemImage: "circle.dashed"
                    )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        ArboreDesign.Colors.softSurface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .padding(.top, 24)
                }

                if let error = controller.errorMessage, mode == .choice {
                    Text(error)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ArboreDesign.Colors.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }

                Spacer()

                primaryButton

                if mode == .choice {
                    Button {
                        controller.cancel()
                        mode = .manualCity
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            cityFieldFocused = true
                        }
                    } label: {
                        Label(
                            L10n.t("GARDEN_LOCATION_MANUAL_CITY"),
                            systemImage: "keyboard"
                        )
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(ArboreDesign.Colors.primaryGreen)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(.plain)

                    Button(L10n.t("GARDEN_LOCATION_SKIP"), action: skip)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(height: 34)
                        .buttonStyle(.plain)
                } else if mode == .manualCity {
                    Button {
                        cityFieldFocused = false
                        mode = .choice
                    } label: {
                        Text(L10n.t("COMMON_BACK"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .onAppear { controller.refreshAuthorizationStatus() }
        .onDisappear { controller.cancel() }
        .onChange(of: controller.location) { _, location in
            guard let location else { return }
            complete(with: location)
        }
        .onChange(of: controller.authorizationStatus) { _, status in
            guard isRequestingLocation else { return }
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                controller.requestFreshLocation()
            case .denied, .restricted:
                isRequestingLocation = false
                mode = .choice
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
        .onChange(of: controller.errorMessage) { _, message in
            guard message != nil else { return }
            isRequestingLocation = false
            mode = .choice
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            controller.refreshAuthorizationStatus()
        }
    }

    private var title: String {
        mode == .manualCity
            ? L10n.t("GARDEN_LOCATION_CITY_TITLE")
            : L10n.t("GARDEN_LOCATION_TITLE")
    }

    private var description: String {
        mode == .manualCity
            ? L10n.t("GARDEN_LOCATION_CITY_DESCRIPTION")
            : L10n.t("GARDEN_LOCATION_DESCRIPTION")
    }

    private var locationIsDenied: Bool {
        controller.authorizationStatus == .denied
            || controller.authorizationStatus == .restricted
    }

    private var manualCityIsValid: Bool {
        manualCity.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private var primaryButton: some View {
        Button(action: primaryAction) {
            HStack(spacing: 9) {
                if mode == .locating {
                    ProgressView().tint(.white)
                    Text(L10n.t("GARDEN_LOCATION_PROGRESS"))
                } else {
                    Text(primaryTitle)
                    Image(systemName: primaryIcon)
                }
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                ArboreDesign.Colors.primaryGreen.opacity(primaryIsEnabled ? 1 : 0.35),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!primaryIsEnabled || mode == .locating)
    }

    private var primaryTitle: String {
        if mode == .manualCity { return L10n.t("COMMON_CONTINUE") }
        if locationIsDenied { return L10n.t("COMMON_OPEN_SETTINGS") }
        return L10n.t("GARDEN_LOCATION_USE")
    }

    private var primaryIcon: String {
        if mode == .manualCity { return "arrow.right" }
        if locationIsDenied { return "gearshape.fill" }
        return "location.fill"
    }

    private var primaryIsEnabled: Bool {
        mode != .manualCity || manualCityIsValid
    }

    private func primaryAction() {
        if mode == .manualCity {
            saveManualCity()
        } else if locationIsDenied {
            openSettings()
        } else {
            mode = .locating
            isRequestingLocation = true
            controller.requestFreshLocation()
        }
    }

    private func saveManualCity() {
        guard manualCityIsValid else { return }
        cityFieldFocused = false
        complete(with: .manualCity(manualCity))
    }

    private func complete(with location: GardenLocationDTO) {
        guard !didComplete else { return }
        didComplete = true
        controller.cancel()
        onReady(location)
    }

    private func skip() {
        guard !didComplete else { return }
        didComplete = true
        controller.cancel()
        onSkip()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private final class FreshGardenLocationController: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var location: GardenLocationDTO?
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var isResolving = false
    private var staleRetryCount = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = manager.authorizationStatus
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = manager.authorizationStatus
    }

    func requestFreshLocation() {
        errorMessage = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard !isResolving else { return }
            isResolving = true
            manager.requestLocation()
        case .denied, .restricted:
            errorMessage = L10n.t("GARDEN_LOCATION_DENIED")
        @unknown default:
            errorMessage = L10n.t("GARDEN_LOCATION_ERROR")
        }
    }

    func cancel() {
        manager.stopUpdatingLocation()
        geocoder.cancelGeocode()
        isResolving = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            self?.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                self?.errorMessage = L10n.t("GARDEN_LOCATION_DENIED")
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let raw = locations.last else { return }
        let age = abs(raw.timestamp.timeIntervalSinceNow)
        if age > 120, staleRetryCount == 0 {
            staleRetryCount += 1
            isResolving = false
            requestFreshLocation()
            return
        }

        let approximate = GardenLocationDTO.deviceApproximate(
            latitude: raw.coordinate.latitude,
            longitude: raw.coordinate.longitude
        )
        guard let latitude = approximate.latitude, let longitude = approximate.longitude else {
            publishError()
            return
        }

        let coarse = CLLocation(latitude: latitude, longitude: longitude)
        geocoder.reverseGeocodeLocation(coarse) { [weak self] placemarks, _ in
            let city = placemarks?.first?.locality ?? placemarks?.first?.subAdministrativeArea
            let result = GardenLocationDTO.deviceApproximate(
                latitude: latitude,
                longitude: longitude,
                city: city
            )
            DispatchQueue.main.async { self?.publish(result) }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.publish(approximate)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        publishError()
    }

    private func publish(_ result: GardenLocationDTO) {
        guard location == nil else { return }
        isResolving = false
        location = result
    }

    private func publishError() {
        DispatchQueue.main.async { [weak self] in
            self?.isResolving = false
            self?.errorMessage = L10n.t("GARDEN_LOCATION_ERROR")
        }
    }
}
