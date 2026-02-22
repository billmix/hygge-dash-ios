import SwiftUI
import Foundation

struct WeatherWidgetView: View {
    @ObservedObject var weatherService: WeatherService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(weatherService.currentTemperature)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(HyggeTheme.textPrimary)
                    .minimumScaleFactor(0.5)

                Image(systemName: weatherService.conditionSymbol)
                    .font(.system(size: 40))
                    .foregroundColor(HyggeTheme.accent)
                    .symbolRenderingMode(.hierarchical)
            }

            HStack(spacing: 8) {
                Text(weatherService.condition)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(HyggeTheme.textSecondary)

                if !weatherService.cityName.isEmpty {
                    Text("•")
                        .foregroundColor(HyggeTheme.textTertiary)
                    Text(weatherService.cityName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(HyggeTheme.textSecondary)
                }
            }

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(HyggeTheme.textTertiary)
                    Text(weatherService.highTemperature)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(HyggeTheme.textSecondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(HyggeTheme.textTertiary)
                    Text(weatherService.lowTemperature)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(HyggeTheme.textSecondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(HyggeTheme.cardBackground)
        .cornerRadius(24)
    }
}

#Preview {
    WeatherWidgetView(weatherService: WeatherService())
        .padding()
        .frame(width: 300, height: 200)
        .background(HyggeTheme.background)
}
