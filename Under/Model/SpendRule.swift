import Foundation

/// One household, one rulebook. Shown once on first launch and linked from
/// Settings and the check-in. The wording lives here so both places agree.
enum SpendRule {
    static let headline = "It counts if you could have said no today without your life breaking."
    static let subhead = "Discretionary only."

    static let doesNotCountTitle = "Doesn't count"
    static let doesNotCount = [
        "Rent or mortgage, utilities, insurance, taxes",
        "Debt payments and paycheck deductions",
        "Subscriptions you already have, on billing day",
        "Planned grocery and household restock",
        "Transfers to savings"
    ]
    static let doesNotCountAside = "Netflix billing day is not a spend day. Thursday Costco is not a spend day."

    static let countsTitle = "Counts"
    static let counts = [
        "Dining out, coffee, delivery",
        "Impulse retail, unplanned Amazon",
        "Entertainment",
        "Starting or upgrading a subscription",
        "\u{201C}While I was there\u{201D} extras",
        "A $14 sandwich grabbed at the grocery store"
    ]

    static let choiceTitle = "Log the choice, not the card."
    static let choiceBody = """
    If you both chose dinner, you both log the bucket for your share of that choice. \
    Who swiped is irrelevant. If your partner bought themselves coffee and you had \
    nothing to do with it, only they log it.
    """

    static let quietDay = "A quiet day is nothing spent, or under $25."
}
