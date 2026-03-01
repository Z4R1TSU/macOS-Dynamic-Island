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
            Image(systemName: weatherManager.weather.condition.sfSymbol)
                .font(.system(size: 24))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)

            Text("\(Int(weatherManager.weather.temperature.rounded()))°")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.white)

            if !weatherManager.weather.cityName.isEmpty {
                Text(weatherManager.weather.cityName)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.6))
                    .lineLimit(1)
            }

            Text(weatherManager.weather.condition.description)
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.5))
                .lineLimit(1)
        }
    }

    // MARK: - Clock Column

    private var clockColumn: some View {
        VStack(spacing: 4) {
            Text(timeString)
                .font(.system(size: 32, weight: .light, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()

            Text(dateString)
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.6))
        }
    }

    // MARK: - Event Column

    private var eventColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Today")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                    .padding(3)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            if let event = nextEvent {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(event.calendar.color))
                        .frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(eventTimeRange(event))
                            .font(.system(size: 9))
                            .foregroundStyle(Color(white: 0.5))
                    }
                }
            } else {
                Text("No events")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.5))
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
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

    private let maxParticles: Int = 60

    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var speed: CGFloat
        var opacity: Double
        var length: CGFloat
        var drift: CGFloat
    }

    var body: some View {
        Canvas { context, size in
            for particle in particles {
                if condition.isSnow {
                    drawSnowflake(context: context, particle: particle, size: size)
                } else {
                    drawRaindrop(context: context, particle: particle, size: size)
                }
            }
        }
        .onAppear { startAnimation() }
        .onDisappear { stopAnimation() }
        .onChange(of: condition) { _, _ in
            particles.removeAll()
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

    private func startAnimation() {
        let intensity = condition.particleIntensity
        let count = Int(Double(maxParticles) * intensity)

        particles = (0..<count).map { _ in
            Particle(
                x: CGFloat.random(in: 0...1),
                y: CGFloat.random(in: -0.3...1),
                speed: CGFloat.random(in: 0.005...0.015) * CGFloat(intensity + 0.5),
                opacity: Double.random(in: 0.15...0.5),
                length: CGFloat.random(in: 4...12),
                drift: CGFloat.random(in: -0.002...0.002)
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
            particles[i].y += particles[i].speed
            particles[i].x += particles[i].drift

            if particles[i].y > 1.1 {
                particles[i].y = CGFloat.random(in: -0.3 ... -0.05)
                particles[i].x = CGFloat.random(in: 0...1)
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
