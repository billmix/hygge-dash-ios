import SwiftUI
import Foundation

struct WeatherWidgetView: View {
    @ObservedObject var weatherService: WeatherService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(weatherService.currentTemperature)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .minimumScaleFactor(0.5)
                
                Image(systemName: weatherService.conditionSymbol)
                    .font(.system(size: 40))
                    .foregroundColor(.black.opacity(0.7))
                    .symbolRenderingMode(.hierarchical)
            }
            
            HStack(spacing: 8) {
                Text(weatherService.condition)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.black.opacity(0.5))

                if !weatherService.cityName.isEmpty {
                    Text("•")
                        .foregroundColor(.black.opacity(0.3))
                    Text(weatherService.cityName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.black.opacity(0.5))
                }
            }

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black.opacity(0.4))
                    Text(weatherService.highTemperature)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black.opacity(0.6))
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black.opacity(0.4))
                    Text(weatherService.lowTemperature)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black.opacity(0.6))
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
    }
}

#Preview {
    WeatherWidgetView(weatherService: WeatherService())
        .padding()
        .frame(width: 300, height: 200)
        .background(Color(.systemGroupedBackground))
}
