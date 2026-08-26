import Foundation

/// Canonical place-name forms, so runs geocoded by different providers group as one place —
/// "Gilbert, AZ, United States" and "Gilbert, Arizona, United States of America" are the same
/// city and must be one pin, one menu row, one count.
enum PlaceNames {

    private static let usStatesByAbbreviation: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
        "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
        "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho",
        "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
        "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
        "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi",
        "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
        "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
        "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
        "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina",
        "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah",
        "VT": "Vermont", "VA": "Virginia", "WA": "Washington", "WV": "West Virginia",
        "WI": "Wisconsin", "WY": "Wyoming", "DC": "District of Columbia",
        "PR": "Puerto Rico"
    ]

    /// A state/region in its canonical full-name form ("AZ" → "Arizona"); anything not a US
    /// abbreviation passes through untouched.
    static func canonicalState(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return raw }
        return usStatesByAbbreviation[raw.uppercased()] ?? raw
    }

    /// A country in its canonical form — the US's several geocoded spellings become one.
    static func canonicalCountry(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return raw }
        switch raw.lowercased() {
        case "usa", "us", "united states of america": return "United States"
        default: return raw
        }
    }
}
