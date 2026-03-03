//
//  WeatherCalendarView.swift
//  boringNotch
//
//  Redesigned calendar widget showing time, date, weather, and next event
//  with weather particle effects (rain/snow).
//

import Defaults
import SwiftUI

struct WeatherCalendarView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var weatherManager = WeatherManager.shared
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.useLiquidGlass) private var useLiquidGlass
    @State private var currentTime = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            if weatherManager.weather.condition.hasParticles {
                WeatherParticleView(condition: weatherManager.weather.condition)
                    .allowsHitTesting(false)
            }

            HStack(spacing: 0) {
                weatherColumn
                    .frame(maxWidth: .infinity)

                dividerLine

                clockColumn
                    .frame(maxWidth: .infinity)

                dividerLine

                eventColumn
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(useLiquidGlass ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onReceive(timer) { time in
            currentTime = time
        }
        .onAppear {
            weatherManager.startMonitoring()
        }
    }

    // MARK: - Weather Column

    private var weatherColumn: some View {
        VStack(spacing: 6) {
            if !weatherManager.locationAuthorized && weatherManager.weather.cityName.isEmpty {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.gray)

                Text("Location")
                    .font(.system(size: 10, weight: .medium))
                    .conditionalModifier(useLiquidGlass) { $0.glassSecondaryText() }
                    .conditionalModifier(!useLiquidGlass) { $0.foregroundStyle(Color(white: 0.5)) }

                Button {
                    weatherManager.startMonitoring()
                } label: {
                    Text("Allow")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.white.opacity(useLiquidGlass ? 0.15 : 0.1))
                        )
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: weatherManager.weather.condition.sfSymbol(isDay: weatherManager.weather.isDay))
                    .font(.system(size: 24))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .conditionalModifier(useLiquidGlass) { $0.glassIcon() }

                Text(weatherManager.weather.isLoaded ? "\(Int(weatherManager.weather.temperature.rounded()))°" : "—")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .adaptiveText(isGlass: useLiquidGlass)

                if !weatherManager.weather.cityName.isEmpty {
                    Text(weatherManager.weather.cityName)
                        .font(.system(size: 10))
                        .conditionalModifier(useLiquidGlass) { $0.glassSecondaryText() }
                        .conditionalModifier(!useLiquidGlass) { $0.foregroundStyle(Color(white: 0.6)) }
                        .lineLimit(1)
                }

                if weatherManager.weather.isLoaded {
                    Text(weatherManager.weather.condition.description)
                        .font(.system(size: 9))
                        .conditionalModifier(useLiquidGlass) { $0.glassSecondaryText() }
                        .conditionalModifier(!useLiquidGlass) { $0.foregroundStyle(Color(white: 0.5)) }
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Clock Column

    private var clockColumn: some View {
        VStack(spacing: 4) {
            Text(timeString)
                .font(.system(size: 32, weight: .light, design: .rounded))
                .monospacedDigit()
                .adaptiveText(isGlass: useLiquidGlass)

            Text(dateString)
                .font(.system(size: 11))
                .conditionalModifier(useLiquidGlass) { $0.glassSecondaryText() }
                .conditionalModifier(!useLiquidGlass) { $0.foregroundStyle(Color(white: 0.6)) }
        }
    }

    // MARK: - Event Column

    private var eventColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Today")
                    .font(.system(size: 13, weight: .semibold))
                    .adaptiveText(isGlass: useLiquidGlass)
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundStyle(useLiquidGlass ? .white.opacity(0.7) : .gray)
                    .padding(3)
                    .background(Color.white.opacity(useLiquidGlass ? 0.12 : 0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            if calendarManager.calendarAuthorizationStatus == .denied
                || calendarManager.calendarAuthorizationStatus == .restricted
            {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No access")
                        .font(.system(size: 10))
                        .conditionalModifier(useLiquidGlass) { $0.glassSecondaryText() }
                        .conditionalModifier(!useLiquidGlass) { $0.foregroundStyle(Color(white: 0.5)) }
                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("Grant Access")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Color.white.opacity(useLiquidGlass ? 0.15 : 0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            } else if calendarManager.calendarAuthorizationStatus == .notDetermined {
                Button {
                    Task { await calendarManager.checkCalendarAuthorization() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 9))
                        Text("Allow Calendar")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.white.opacity(useLiquidGlass ? 0.15 : 0.1))
                    )
                }
                .buttonStyle(.plain)
            } else if let event = nextEvent {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(event.calendar.color))
                        .frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title)
                            .font(.system(size: 11, weight: .medium))
                            .adaptiveText(isGlass: useLiquidGlass)
                            .lineLimit(1)
                        Text(eventTimeRange(event))
                            .font(.system(size: 9))
                            .conditionalModifier(useLiquidGlass) { $0.glassSecondaryText() }
                            .conditionalModifier(!useLiquidGlass) { $0.foregroundStyle(Color(white: 0.5)) }
                    }
                }
            } else {
                Text("No events")
                    .font(.system(size: 11))
                    .conditionalModifier(useLiquidGlass) { $0.glassSecondaryText() }
                    .conditionalModifier(!useLiquidGlass) { $0.foregroundStyle(Color(white: 0.5)) }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.white.opacity(useLiquidGlass ? 0.15 : 0.1))
            .frame(width: 1, height: 60)
    }

    private var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: currentTime)
    }

    private var dateString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, d MMM"
        return fmt.string(from: currentTime)
    }

    private var nextEvent: EventModel? {
        let now = Date()
        return calendarManager.events
            .filter { !$0.type.isReminder && $0.end > now }
            .sorted { $0.start < $1.start }
            .first
    }

    private func eventTimeRange(_ event: EventModel) -> String {
        if event.isAllDay { return "All-day" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: event.start)) – \(fmt.string(from: event.end))"
    }
}

// MARK: - Weather Particle Effect

struct WeatherParticleView: View {
    let condition: WeatherCondition
    @State private var particles: [Particle] = []
    @State private var animationTimer: Timer?

    private var maxParticles: Int {
        condition.isSunny ? 15 : condition.isCloudy ? 8 : 60
    }

    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var speed: CGFloat
        var opacity: Double
        var length: CGFloat
        var drift: CGFloat
        var phase: CGFloat = 0
    }

    var body: some View {
        Canvas { context, size in
            for particle in particles {
                if condition.isSnow {
                    drawSnowflake(context: context, particle: particle, size: size)
                } else if condition.isSunny {
                    drawSparkle(context: context, particle: particle, size: size)
                } else if condition.isCloudy {
                    drawCloudDrift(context: context, particle: particle, size: size)
                } else {
                    drawRaindrop(context: context, particle: particle, size: size)
                }
            }
        }
        .onAppear { startAnimation() }
        .onDisappear { stopAnimation() }
        .onChange(of: condition) { _, _ in
            particles.removeAll()
            startAnimation()
        }
    }

    private func drawRaindrop(context: GraphicsContext, particle: Particle, size: CGSize) {
        let x = particle.x * size.width
        let y = particle.y * size.height
        var path = Path()
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x + particle.drift * 2, y: y + particle.length))
        context.stroke(path, with: .color(.white.opacity(particle.opacity)), lineWidth: 0.8)
    }

    private func drawSnowflake(context: GraphicsContext, particle: Particle, size: CGSize) {
        let x = particle.x * size.width
        let y = particle.y * size.height
        let r = particle.length * 0.3
        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
        context.fill(Ellipse().path(in: rect), with: .color(.white.opacity(particle.opacity)))
    }

    private func drawSparkle(context: GraphicsContext, particle: Particle, size: CGSize) {
        let x = particle.x * size.width
        let y = particle.y * size.height
        let pulse = (sin(particle.phase) + 1) / 2
        let r = particle.length * 0.15 * (0.5 + pulse * 0.5)
        let alpha = particle.opacity * (0.3 + pulse * 0.7)
        let color = Color(hue: 0.12, saturation: 0.15, brightness: 1.0)
        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
        context.fill(Ellipse().path(in: rect), with: .color(color.opacity(alpha)))
        let glowRect = rect.insetBy(dx: -r * 0.6, dy: -r * 0.6)
        context.fill(Ellipse().path(in: glowRect), with: .color(color.opacity(alpha * 0.2)))
    }

    private func drawCloudDrift(context: GraphicsContext, particle: Particle, size: CGSize) {
        let x = particle.x * size.width
        let y = particle.y * size.height
        let w = particle.length * 3
        let h = particle.length * 1.2
        let rect = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
        context.fill(
            RoundedRectangle(cornerRadius: h / 2).path(in: rect),
            with: .color(.white.opacity(particle.opacity * 0.4))
        )
    }

    private func startAnimation() {
        let intensity = condition.particleIntensity
        let count = Int(Double(maxParticles) * max(intensity, 0.2))

        particles = (0..<count).map { _ in
            Particle(
                x: CGFloat.random(in: 0...1),
                y: condition.isSunny || condition.isCloudy
                    ? CGFloat.random(in: 0...1)
                    : CGFloat.random(in: -0.3...1),
                speed: condition.isSunny
                    ? 0
                    : condition.isCloudy
                        ? CGFloat.random(in: 0.0005...0.001)
                        : CGFloat.random(in: 0.005...0.015) * CGFloat(intensity + 0.5),
                opacity: condition.isSunny
                    ? Double.random(in: 0.3...0.8)
                    : condition.isCloudy
                        ? Double.random(in: 0.03...0.08)
                        : Double.random(in: 0.15...0.5),
                length: CGFloat.random(in: 4...12),
                drift: condition.isCloudy
                    ? CGFloat.random(in: 0.0005...0.002)
                    : CGFloat.random(in: -0.002...0.002),
                phase: CGFloat.random(in: 0...(2 * .pi))
            )
        }

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
                updateParticles()
            }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func updateParticles() {
        for i in particles.indices {
            if condition.isSunny {
                particles[i].phase += CGFloat.random(in: 0.03...0.08)
            } else if condition.isCloudy {
                particles[i].x += particles[i].drift
                particles[i].y += particles[i].speed
                if particles[i].x > 1.3 {
                    particles[i].x = -0.3
                    particles[i].y = CGFloat.random(in: 0...1)
                }
            } else {
                particles[i].y += particles[i].speed
                particles[i].x += particles[i].drift
                if particles[i].y > 1.1 {
                    particles[i].y = CGFloat.random(in: -0.3 ... -0.05)
                    particles[i].x = CGFloat.random(in: 0...1)
                }
            }
        }
    }
}

#Preview {
    WeatherCalendarView()
        .frame(width: 340, height: 130)
        .background(.black)
        .environmentObject(BoringViewModel())
}
