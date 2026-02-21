import SwiftUI

// Cozy house with radiating warmth lines
struct AppIconGenerator: View {
    var body: some View {
        ZStack {
            Color.white

            // Radiating glow lines behind house
            ForEach(0..<12) { i in
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 8, height: 300)
                    .offset(y: -220)
                    .rotationEffect(.degrees(Double(i) * 30))
            }

            // Soft glow circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.black.opacity(0.12), .clear],
                        center: .center,
                        startRadius: 50,
                        endRadius: 350
                    )
                )
                .frame(width: 700, height: 700)

            // House
            Image(systemName: "house.fill")
                .font(.system(size: 380, weight: .regular))
                .foregroundColor(.black)
        }
        .frame(width: 1024, height: 1024)
    }
}

// House with warm window glow effect
struct AppIconGeneratorAlt1: View {
    var body: some View {
        ZStack {
            Color.white

            // Glow emanating from behind
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.black.opacity(0.2), .black.opacity(0.05), .clear],
                        center: .center,
                        startRadius: 100,
                        endRadius: 400
                    )
                )
                .frame(width: 800, height: 800)

            // House outline with thick stroke
            Image(systemName: "house")
                .font(.system(size: 400, weight: .light))
                .foregroundColor(.black)

            // Inner glow dot (representing warmth inside)
            Circle()
                .fill(.black.opacity(0.15))
                .frame(width: 80, height: 80)
                .offset(y: 60)
        }
        .frame(width: 1024, height: 1024)
    }
}

// Dark cozy - inverted with glow
struct AppIconGeneratorAlt2: View {
    var body: some View {
        ZStack {
            Color.black

            // Warm glow behind house
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.1), .clear],
                        center: .center,
                        startRadius: 80,
                        endRadius: 380
                    )
                )
                .frame(width: 760, height: 760)

            // House
            Image(systemName: "house.fill")
                .font(.system(size: 380, weight: .regular))
                .foregroundColor(.white)
        }
        .frame(width: 1024, height: 1024)
    }
}

// Minimal with subtle halo
struct AppIconGeneratorAlt3: View {
    var body: some View {
        ZStack {
            Color.white

            // Subtle halo
            Circle()
                .stroke(Color.black.opacity(0.1), lineWidth: 60)
                .frame(width: 600, height: 600)
                .blur(radius: 30)

            // House
            Image(systemName: "house.fill")
                .font(.system(size: 350, weight: .regular))
                .foregroundColor(.black)
        }
        .frame(width: 1024, height: 1024)
    }
}

#Preview("Radiating warmth") {
    AppIconGenerator()
}

#Preview("Glowing outline") {
    AppIconGeneratorAlt1()
}

#Preview("Dark with glow") {
    AppIconGeneratorAlt2()
}

#Preview("Subtle halo") {
    AppIconGeneratorAlt3()
}
