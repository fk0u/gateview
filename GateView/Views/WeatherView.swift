import SwiftUI

struct WeatherView: View {
    let weather: Weather

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: weather.symbol).symbolRenderingMode(.multicolor)
            Text("\(weather.temperature)°").monospacedDigit()
            Text(weather.label).opacity(0.75)
        }
        .font(.system(size: 22, weight: .regular))
    }
}
