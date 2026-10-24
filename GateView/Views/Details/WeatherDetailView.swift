import SwiftUI

struct WeatherDetailView: View {
    let weather: Weather
    let city: String
    var lang: String = "id"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailHeader(title: "Cuaca · \(city)", symbol: "cloud.sun.fill")
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: weather.symbol).symbolRenderingMode(.multicolor).font(.system(size: 44))
                VStack(alignment: .leading) {
                    Text("\(weather.temperature)°").font(.system(size: 44, weight: .light).monospacedDigit())
                    Text(weather.label).opacity(0.75)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Label("Terasa \(weather.feelsLike)°", systemImage: "thermometer.medium")
                    Label("\(weather.humidity)%", systemImage: "humidity.fill")
                    Label("\(weather.wind) km/j", systemImage: "wind")
                }
                .font(.caption).opacity(0.75)
            }
            if let aqi = weather.aqi {
                airQuality(aqi)
            }

            HStack(spacing: 0) {
                ForEach(weather.hourly.prefix(8)) { hour in
                    VStack(spacing: 6) {
                        Text(hour.time, format: .dateTime.hour(.twoDigits(amPM: .omitted))).font(.caption2).opacity(0.6)
                        Image(systemName: hour.symbol).symbolRenderingMode(.multicolor)
                        Text("\(hour.temperature)°").font(.callout.monospacedDigit())
                        Text(hour.rainChance > 0 ? "\(hour.rainChance)%" : " ")
                            .font(.system(size: 9).monospacedDigit()).foregroundStyle(.cyan)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Divider().overlay(.white.opacity(0.15))
            let low = weather.daily.map(\.min).min() ?? 0
            let high = weather.daily.map(\.max).max() ?? 1
            ForEach(weather.daily) { day in
                HStack(spacing: 10) {
                    Text(day.date, format: .dateTime.weekday(.abbreviated)).frame(width: 40, alignment: .leading)
                    Image(systemName: day.symbol).symbolRenderingMode(.multicolor).frame(width: 24)
                    Text(day.rainChance > 0 ? "\(day.rainChance)%" : "").font(.caption2).foregroundStyle(.cyan).frame(width: 30)
                    Text("\(day.min)°").opacity(0.6).frame(width: 30, alignment: .trailing)
                    RangeBar(low: low, high: high, from: day.min, to: day.max)
                    Text("\(day.max)°").frame(width: 30, alignment: .leading)
                }
                .font(.callout.monospacedDigit())
            }
        }
    }
    private func airQuality(_ aqi: Int) -> some View {
        let (hex, idLabel) = WeatherService.airQualityBand(aqi)
        let en = ["Baik": "Good", "Sedang": "Moderate", "Tidak Sehat (Sensitif)": "Unhealthy (Sensitive)",
                  "Tidak Sehat": "Unhealthy", "Sangat Tidak Sehat": "Very Unhealthy", "Berbahaya": "Hazardous"][idLabel] ?? idLabel
        return HStack(spacing: 8) {
            Circle().fill(Color(hex: hex) ?? .green).frame(width: 8, height: 8)
            Text(L10n.tr(lang, idLabel, en)).font(.caption.weight(.medium))
            Text("US AQI \(aqi)").font(.caption.monospacedDigit()).opacity(0.6)
            if let pm = weather.pm25 {
                Text("PM2.5 \(Int(pm.rounded()))").font(.caption.monospacedDigit()).opacity(0.6)
            }
            Spacer()
            Text(L10n.tr(lang, "Kualitas udara", "Air quality")).font(.caption2).opacity(0.45)
        }
    }
}

private struct RangeBar: View {
    let low: Int, high: Int, from: Int, to: Int

    var body: some View {
        GeometryReader { geo in
            let span = CGFloat(max(high - low, 1))
            Capsule().fill(.white.opacity(0.12))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * CGFloat(to - from) / span))
                        .offset(x: geo.size.width * CGFloat(from - low) / span)
                }
        }
        .frame(height: 5)
    }
}
