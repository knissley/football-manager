import FMCore
import FMRandom

/// Generates the people who are not players, and replaces them as they retire.
///
/// A league that runs for fifty seasons needs roughly five generations of
/// coaches, scouts, agents, writers and officials. Turnover is not decoration:
/// a world where the same columnist covers your entire career, or where the
/// coordinator you hired in season one is still working in season forty, reads
/// as a fixture rather than a place.
public enum PersonnelGenerator {

    /// One person in a role, at a plausible point in their career.
    ///
    /// `careerStage` places them along it: 0 is a newcomer, 1 is about to
    /// retire. Generating a league needs a spread, or everyone steps away in the
    /// same offseason.
    public static func person(
        id: PersonnelID,
        role: PersonnelRole,
        season: Int,
        careerStage: Double,
        using random: inout SplittableRandom
    ) -> Personnel {
        let span = CareerSpan.span(for: role)

        let retirementAge = random.nextInt(in: span.retirementAge)
        let entryAge = random.nextInt(in: span.entryAge)

        // Where along the career they currently are.
        let stage = min(max(careerStage, 0), 1)
        let workingYears = max(1, retirementAge - entryAge)
        let yearsIn = Rounding.toNearest(
            Double(workingYears) * stage, clampedTo: 0...(workingYears - 1))

        let age = entryAge + yearsIn

        return Personnel(
            id: id,
            name: NameGenerator.personName(using: &random),
            birthSeason: season - age,
            role: role,
            careerStartSeason: season - yearsIn,
            retirementAge: retirementAge
        )
    }

    /// A fresh newcomer to a role, for replacing someone who has stepped away.
    public static func newcomer(
        id: PersonnelID, role: PersonnelRole, season: Int, using random: inout SplittableRandom
    ) -> Personnel {
        person(id: id, role: role, season: season, careerStage: 0, using: &random)
    }

    /// A cohort in a role, spread across their careers.
    ///
    /// The spread is the point. Generating everyone at the same stage would mean
    /// an entire profession retiring together, and then again in lockstep a
    /// generation later.
    public static func cohort(
        role: PersonnelRole,
        count: Int,
        season: Int,
        ids: inout IdentifierSequence<PersonnelSubject>,
        using random: inout SplittableRandom
    ) -> [Personnel] {
        precondition(count >= 0, "a cohort cannot be negative")
        guard count > 0 else { return [] }

        return (0..<count).map { index in
            // Evenly spaced stages, jittered so the turnover is not metronomic.
            let base = count == 1 ? 0.5 : Double(index) / Double(count - 1)
            let jitter = random.nextDouble(in: -0.08..<0.08)
            return person(
                id: ids.allocate(), role: role, season: season,
                careerStage: base + jitter, using: &random)
        }
    }

    /// Who is stepping away after this season, and the newcomers replacing them.
    ///
    /// Replacement is one-for-one so a profession keeps its size. Whether a
    /// *team* fills a vacancy with the newcomer or hires someone established
    /// from elsewhere is a hiring decision, not a generation one.
    public static func turnover(
        among personnel: [Personnel],
        after season: Int,
        ids: inout IdentifierSequence<PersonnelSubject>,
        using random: inout SplittableRandom
    ) -> (retiring: [Personnel], newcomers: [Personnel]) {
        // Sorted by identifier so the result never depends on the order the
        // collection happened to arrive in.
        let retiring =
            personnel
            .filter { $0.retires(after: season) }
            .sorted { $0.id < $1.id }

        let newcomers = retiring.map { departing in
            newcomer(
                id: ids.allocate(), role: departing.role, season: season + 1, using: &random)
        }

        return (retiring, newcomers)
    }
}
