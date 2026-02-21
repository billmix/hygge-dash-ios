import Foundation
import Combine

class QuotesService: ObservableObject {
    @Published var currentQuote: Quote

    private let quotes: [Quote] = [
        // Marcus Aurelius
        Quote(text: "You have power over your mind - not outside events. Realize this, and you will find strength.", author: "Marcus Aurelius"),
        Quote(text: "The happiness of your life depends upon the quality of your thoughts.", author: "Marcus Aurelius"),
        Quote(text: "Waste no more time arguing about what a good man should be. Be one.", author: "Marcus Aurelius"),
        Quote(text: "Very little is needed to make a happy life; it is all within yourself, in your way of thinking.", author: "Marcus Aurelius"),
        Quote(text: "When you arise in the morning, think of what a precious privilege it is to be alive.", author: "Marcus Aurelius"),
        Quote(text: "The best revenge is not to be like your enemy.", author: "Marcus Aurelius"),
        Quote(text: "Accept the things to which fate binds you, and love the people with whom fate brings you together.", author: "Marcus Aurelius"),
        Quote(text: "It is not death that a man should fear, but he should fear never beginning to live.", author: "Marcus Aurelius"),
        Quote(text: "Never let the future disturb you. You will meet it with the same weapons of reason.", author: "Marcus Aurelius"),
        Quote(text: "The soul becomes dyed with the color of its thoughts.", author: "Marcus Aurelius"),
        Quote(text: "How much more grievous are the consequences of anger than the causes of it.", author: "Marcus Aurelius"),
        Quote(text: "Begin each day by telling yourself: Today I shall be meeting with interference, ingratitude, insolence, disloyalty.", author: "Marcus Aurelius"),
        Quote(text: "Everything we hear is an opinion, not a fact. Everything we see is a perspective, not the truth.", author: "Marcus Aurelius"),
        Quote(text: "Dwell on the beauty of life. Watch the stars, and see yourself running with them.", author: "Marcus Aurelius"),
        Quote(text: "The object of life is not to be on the side of the majority, but to escape finding oneself among the ranks of the insane.", author: "Marcus Aurelius"),

        // Seneca
        Quote(text: "We suffer more often in imagination than in reality.", author: "Seneca"),
        Quote(text: "Luck is what happens when preparation meets opportunity.", author: "Seneca"),
        Quote(text: "It is not that we have a short time to live, but that we waste a lot of it.", author: "Seneca"),
        Quote(text: "Difficulties strengthen the mind, as labor does the body.", author: "Seneca"),
        Quote(text: "True happiness is to enjoy the present, without anxious dependence upon the future.", author: "Seneca"),
        Quote(text: "He who is brave is free.", author: "Seneca"),
        Quote(text: "No man was ever wise by chance.", author: "Seneca"),
        Quote(text: "Begin at once to live, and count each separate day as a separate life.", author: "Seneca"),
        Quote(text: "Sometimes even to live is an act of courage.", author: "Seneca"),
        Quote(text: "As is a tale, so is life: not how long it is, but how good it is, is what matters.", author: "Seneca"),
        Quote(text: "Religion is regarded by the common people as true, by the wise as false, and by rulers as useful.", author: "Seneca"),
        Quote(text: "If a man knows not to which port he sails, no wind is favorable.", author: "Seneca"),
        Quote(text: "A gem cannot be polished without friction, nor a man perfected without trials.", author: "Seneca"),
        Quote(text: "Hang on to your youthful enthusiasms - you'll be able to use them better when you're older.", author: "Seneca"),
        Quote(text: "Life is long if you know how to use it.", author: "Seneca"),
        Quote(text: "We are more often frightened than hurt; and we suffer more from imagination than from reality.", author: "Seneca"),
        Quote(text: "The whole future lies in uncertainty: live immediately.", author: "Seneca"),

        // Epictetus
        Quote(text: "It's not what happens to you, but how you react to it that matters.", author: "Epictetus"),
        Quote(text: "Man is not worried by real problems so much as by his imagined anxieties about real problems.", author: "Epictetus"),
        Quote(text: "First say to yourself what you would be; and then do what you have to do.", author: "Epictetus"),
        Quote(text: "There is only one way to happiness and that is to cease worrying about things beyond our power.", author: "Epictetus"),
        Quote(text: "Make the best use of what is in your power, and take the rest as it happens.", author: "Epictetus"),
        Quote(text: "No man is free who is not master of himself.", author: "Epictetus"),
        Quote(text: "Don't explain your philosophy. Embody it.", author: "Epictetus"),
        Quote(text: "Wealth consists not in having great possessions, but in having few wants.", author: "Epictetus"),
        Quote(text: "If you want to improve, be content to be thought foolish and stupid.", author: "Epictetus"),
        Quote(text: "He is a wise man who does not grieve for the things which he has not, but rejoices for those which he has.", author: "Epictetus"),
        Quote(text: "Only the educated are free.", author: "Epictetus"),
        Quote(text: "Circumstances don't make the man, they only reveal him to himself.", author: "Epictetus"),
        Quote(text: "Freedom is the only worthy goal in life. It is won by disregarding things that lie beyond our control.", author: "Epictetus"),
        Quote(text: "Any person capable of angering you becomes your master.", author: "Epictetus"),
        Quote(text: "He who laughs at himself never runs out of things to laugh at.", author: "Epictetus"),

        // Zeno of Citium
        Quote(text: "We have two ears and one mouth, so we should listen more than we speak.", author: "Zeno of Citium"),
        Quote(text: "Man conquers the world by conquering himself.", author: "Zeno of Citium"),
        Quote(text: "Well-being is realized by small steps, but is truly no small thing.", author: "Zeno of Citium"),

        // Cleanthes
        Quote(text: "Lead me, Zeus, and you, Fate, wherever you have assigned me to go.", author: "Cleanthes"),

        // Cato the Younger
        Quote(text: "I would rather be right than be consistent.", author: "Cato the Younger"),
    ]

    private var dailyQuoteIndex: Int {
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return dayOfYear % quotes.count
    }

    init() {
        currentQuote = quotes[0]
        showDailyQuote()
    }

    func showRandomQuote() {
        var newQuote: Quote
        repeat {
            newQuote = quotes.randomElement() ?? quotes[0]
        } while newQuote == currentQuote && quotes.count > 1
        currentQuote = newQuote
    }

    func showDailyQuote() {
        currentQuote = quotes[dailyQuoteIndex]
    }
}
