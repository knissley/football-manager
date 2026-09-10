import FMCore
import FMRandom
import Testing

@testable import FMGeneration

private let season = 2030

@Suite("Personnel lifecycle")
struct PersonnelLifecycleTests {

    @Test("Career spans differ by role and are internally coherent", .tags(.unit))
    func spans() {
        for role in PersonnelRole.allCases {
            let span = CareerSpan.span(for: role)
            #expect(span.entryAge.lowerBound < span.retirementAge.lowerBound, "\(role)")
            #expect(span.entryAge.upperBound < span.retirementAge.upperBound, "\(role)")
            #expect(span.entryAge.lowerBound >= 20, "\(role) starts implausibly young")
            #expect(span.retirementAge.upperBound <= 80, "\(role) works implausibly late")
        }
    }

    /// A coach's career is a different shape from a player's, not just longer.
    @Test("Coaches work far later than players", .tags(.unit))
    func coachesOutlastPlayers() {
        let coach = CareerSpan.span(for: .headCoach)
        #expect(coach.entryAge.lowerBound > 30)
        #expect(coach.retirementAge.lowerBound > 55)
    }

    @Test("Activity and retirement follow from age", .tags(.unit))
    func activity() {
        let person = Personnel(
            id: PersonnelID(1), name: PersonName(given: "Ada", family: "Halstead"),
            birthSeason: 1980, role: .writer, careerStartSeason: 2010, retirementAge: 65)

        #expect(person.age(in: 2030) == 50)
        #expect(person.experience(in: 2030) == 20)
        #expect(person.isActive(in: 2030))
        #expect(person.retirementSeason == 2045)
        #expect(!person.isActive(in: 2045))
        #expect(person.retires(after: 2044))
        #expect(!person.retires(after: 2030))
        #expect(!person.isActive(in: 2005), "active before their career began")
    }
}

@Suite("Personnel generation")
struct PersonnelGeneratorTests {

    private func cohort(
        role: PersonnelRole = .scout, count: Int = 40, seed: UInt64 = 1
    ) -> [Personnel] {
        var random = SplittableRandom(seed: seed)
        var ids = IdentifierSequence<PersonnelSubject>()
        return PersonnelGenerator.cohort(
            role: role, count: count, season: season, ids: &ids, using: &random)
    }

    @Test("Generation is deterministic", .tags(.contract))
    func deterministic() {
        #expect(cohort(seed: 77) == cohort(seed: 77))
    }

    @Test("Everyone generated is currently working", .tags(.unit))
    func allActive() {
        for role in PersonnelRole.allCases {
            for person in cohort(role: role, count: 30, seed: 5) {
                #expect(person.isActive(in: season), "\(role) generated already retired")
                #expect(person.age(in: season) < person.retirementAge)
                #expect(person.careerStartSeason <= season)
            }
        }
    }

    /// The failure this guards against: generate a profession all at the same
    /// stage and it retires in a single offseason, then again in lockstep a
    /// generation later.
    @Test("A cohort is spread across its careers", .tags(.unit))
    func spreadAcrossCareers() {
        let people = cohort(count: 60)
        let experience = people.map { $0.experience(in: season) }
        guard let youngest = experience.min(), let oldest = experience.max() else {
            Issue.record("no personnel generated")
            return
        }
        #expect(youngest <= 2, "nobody is new to the job")
        #expect(oldest >= 15, "nobody is near the end")

        // No single season should claim more than a fifth of the profession.
        var byRetirement: [Int: Int] = [:]
        for person in people { byRetirement[person.retirementSeason, default: 0] += 1 }
        let worst = byRetirement.values.max() ?? 0
        #expect(worst <= people.count / 5, "\(worst) of \(people.count) retire together")
    }

    @Test("Ages are plausible for the role", .tags(.unit))
    func plausibleAges() {
        for role in PersonnelRole.allCases {
            let ages = cohort(role: role, count: 40, seed: 9).map { $0.age(in: season) }
            let span = CareerSpan.span(for: role)
            for age in ages {
                #expect(age >= span.entryAge.lowerBound, "\(role) aged \(age)")
                #expect(age <= span.retirementAge.upperBound, "\(role) aged \(age)")
            }
        }
    }

    @Test("A newcomer is at the start of their career", .tags(.unit))
    func newcomers() {
        var random = SplittableRandom(seed: 13)
        for role in PersonnelRole.allCases {
            let person = PersonnelGenerator.newcomer(
                id: PersonnelID(1), role: role, season: season, using: &random)
            #expect(person.experience(in: season) == 0)
            #expect(person.careerStartSeason == season)
            #expect(person.isActive(in: season))
        }
    }

    @Test("Turnover retires the right people and replaces them one for one", .tags(.unit))
    func turnover() {
        var random = SplittableRandom(seed: 21)
        var ids = IdentifierSequence<PersonnelSubject>()
        let people = PersonnelGenerator.cohort(
            role: .official, count: 50, season: season, ids: &ids, using: &random)

        let result = PersonnelGenerator.turnover(
            among: people, after: season, ids: &ids, using: &random)

        #expect(result.retiring.count == result.newcomers.count)
        for departing in result.retiring {
            #expect(departing.retires(after: season))
        }
        for arriving in result.newcomers {
            #expect(arriving.isActive(in: season + 1))
            #expect(arriving.experience(in: season + 1) == 0)
        }
        #expect(Set(result.newcomers.map(\.id)).isDisjoint(with: Set(people.map(\.id))))
    }

    /// The point of the whole thing: run a career out fifty seasons and the
    /// people covering it should not be the people who started it.
    @Test("A profession turns over across a long career", .tags(.unit))
    func turnsOverAcrossFiftySeasons() {
        var random = SplittableRandom(seed: 31)
        var ids = IdentifierSequence<PersonnelSubject>()
        var people = PersonnelGenerator.cohort(
            role: .writer, count: 24, season: season, ids: &ids, using: &random)
        let original = Set(people.map(\.id))

        var totalRetired = 0
        for offset in 0..<50 {
            let current = season + offset
            let result = PersonnelGenerator.turnover(
                among: people, after: current, ids: &ids, using: &random)
            totalRetired += result.retiring.count
            let leaving = Set(result.retiring.map(\.id))
            people = people.filter { !leaving.contains($0.id) } + result.newcomers
        }

        #expect(people.count == 24, "the profession changed size")
        #expect(totalRetired >= 24, "only \(totalRetired) retirements in fifty seasons")

        let survivors = people.filter { original.contains($0.id) }
        #expect(
            survivors.isEmpty, "\(survivors.count) of the originals still working after 50 years")
    }

    @Test("Nobody works past their retirement age", .tags(.unit))
    func nobodyOverstays() {
        var random = SplittableRandom(seed: 41)
        var ids = IdentifierSequence<PersonnelSubject>()
        var people = PersonnelGenerator.cohort(
            role: .headCoach, count: 32, season: season, ids: &ids, using: &random)

        for offset in 0..<40 {
            let current = season + offset
            for person in people {
                #expect(person.isActive(in: current), "\(person.name) worked past retirement")
            }
            let result = PersonnelGenerator.turnover(
                among: people, after: current, ids: &ids, using: &random)
            let leaving = Set(result.retiring.map(\.id))
            people = people.filter { !leaving.contains($0.id) } + result.newcomers
        }
    }
}
