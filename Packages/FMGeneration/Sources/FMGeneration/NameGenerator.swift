import FMCore
import FMRandom

/// Generates people and the places they came from.
///
/// Every draw comes from the supplied generator, so a world is reproducible from
/// its seed down to the last name on the practice squad.
public enum NameGenerator {

    /// Roughly how often a name carries a suffix.
    private static let suffixProbability = 0.04

    public static func personName(using random: inout SplittableRandom) -> PersonName {
        let given = NamePools.given[Int(random.next(upperBound: UInt64(NamePools.given.count)))]
        let family = NamePools.family[Int(random.next(upperBound: UInt64(NamePools.family.count)))]

        guard random.nextBool(probability: suffixProbability) else {
            return PersonName(given: given, family: family)
        }
        let suffix =
            NamePools.suffixes[Int(random.next(upperBound: UInt64(NamePools.suffixes.count)))]
        return PersonName(given: given, family: family, suffix: suffix)
    }

    /// A fictional college, weighted so that most prospects come from programmes
    /// with tape on them and a minority come from places nobody has watched.
    public static func college(using random: inout SplittableRandom) -> College {
        let place = CollegePools.places[
            Int(random.next(upperBound: UInt64(CollegePools.places.count)))]
        let kind = CollegePools.kinds[
            Int(random.next(upperBound: UInt64(CollegePools.kinds.count)))]

        var name = "\(place) \(kind)"
        if random.nextBool(probability: 0.2) {
            let direction =
                CollegePools.directions[
                    Int(random.next(upperBound: UInt64(CollegePools.directions.count)))]
            name = "\(direction) \(place) \(kind)"
        }

        // Most prospects come from programmes that get watched.
        let profile: CollegeProfile
        switch random.next(upperBound: 100) {
        case ..<45: profile = .powerProgram
        case ..<80: profile = .midMajor
        default: profile = .smallSchool
        }

        return College(name: name, profile: profile)
    }

    /// A pool of colleges for a world, generated once so that prospects share
    /// alma maters and a programme can build a reputation over a career.
    public static func collegePool(
        count: Int, using random: inout SplittableRandom
    ) -> [College] {
        precondition(count > 0, "a world needs at least one college")
        var colleges: [College] = []
        var seen: Set<String> = []
        // Bounded attempts: the name space is finite, and a world with a few
        // duplicate programme names is better than one that fails to generate.
        for _ in 0..<(count * 4) where colleges.count < count {
            let college = college(using: &random)
            if seen.insert(college.name).inserted {
                colleges.append(college)
            }
        }
        return colleges
    }
}
