import SwiftUI

struct QuotesView: View {
    @ObservedObject var quotesService: QuotesService
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()

            quoteContent

            Spacer()

            refreshButton
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .cornerRadius(32)
        .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 8)
    }

    private var quoteContent: some View {
        GeometryReader { geometry in
            VStack(spacing: 24) {
                Text(quotesService.currentQuote.text)
                    .font(.system(size: 60, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .lineSpacing(12)
                    .minimumScaleFactor(0.3)
                    .lineLimit(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(isAnimating ? 1 : 0)
                    .animation(.easeIn(duration: 0.5), value: isAnimating)

                Text("— \(quotesService.currentQuote.author)")
                    .font(.system(size: 28, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                    .opacity(isAnimating ? 1 : 0)
                    .animation(.easeIn(duration: 0.5).delay(0.2), value: isAnimating)
            }
            .padding(.horizontal)
        }
        .onAppear {
            isAnimating = true
        }
        .onChange(of: quotesService.currentQuote) { _, _ in
            isAnimating = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isAnimating = true
            }
        }
    }

    private var refreshButton: some View {
        HStack {
            Spacer()
            Button(action: {
                withAnimation {
                    quotesService.showRandomQuote()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("New Quote")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.15))
                .foregroundColor(.white)
                .cornerRadius(20)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }
}

#Preview {
    QuotesView(quotesService: QuotesService())
        .padding()
        .background(Color(.systemGroupedBackground))
        .frame(height: 400)
}
