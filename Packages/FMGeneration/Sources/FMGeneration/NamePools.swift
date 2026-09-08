/// Name components, drawn from cultural commons and combined freely.
///
/// Deliberately *not* scraped from any roster. These are ordinary given names
/// and surnames; a generated player who happens to share a name with a real one
/// is a coincidence of the kind that occurs between real people constantly.
///
/// Pool sizes are a starting point. Roughly 150 x 190 gives ~28,000
/// combinations, which produces occasional repeats across a decade of draft
/// classes — which is what real leagues look like. Expand rather than
/// de-duplicate.
enum NamePools {

    static let given: [String] = [
        "Aaron", "Adrian", "Ahmad", "Alec", "Andre", "Angelo", "Anthony", "Antoine",
        "Austin", "Avery", "Barrett", "Beau", "Blake", "Brandon", "Braxton", "Brendan",
        "Brennan", "Brett", "Brody", "Bryce", "Caleb", "Cameron", "Carson", "Cedric",
        "Chandler", "Chase", "Clay", "Cody", "Colby", "Cole", "Colin", "Connor",
        "Corey", "Craig", "Curtis", "Dallas", "Damien", "Damon", "Daniel", "Darius",
        "Darnell", "Davis", "Deacon", "Declan", "Demetrius", "Derek", "Deshawn", "Devin",
        "Dominic", "Donovan", "Drew", "Duane", "Dustin", "Dwight", "Eli", "Elijah",
        "Emmett", "Eric", "Ethan", "Evan", "Ezra", "Felix", "Finn", "Franklin",
        "Gabriel", "Garrett", "Gavin", "Grant", "Grayson", "Gregory", "Hayden", "Hendrix",
        "Holden", "Hunter", "Ian", "Isaiah", "Jabari", "Jackson", "Jaden", "Jamal",
        "Jared", "Jarrett", "Jasper", "Javon", "Jaxon", "Jeremiah", "Jerome", "Jesse",
        "Jonah", "Jordan", "Josiah", "Julian", "Justice", "Kaden", "Kai", "Keenan",
        "Keegan", "Kendrick", "Kenneth", "Kevon", "Khalil", "Kingston", "Knox", "Kyler",
        "Lamar", "Lance", "Landon", "Lawson", "Leland", "Levi", "Lincoln", "Logan",
        "Lorenzo", "Lucas", "Malachi", "Malik", "Marcus", "Mario", "Marshall", "Mason",
        "Maurice", "Maverick", "Micah", "Miles", "Mitchell", "Montrell", "Nash", "Nathaniel",
        "Nolan", "Omar", "Orlando", "Owen", "Parker", "Patrick", "Percy", "Peyton",
        "Phillip", "Pierce", "Quentin", "Quincy", "Raheem", "Ramon", "Reggie", "Reuben",
        "Rhett", "Rico", "Riley", "Rodney", "Roman", "Ronin", "Rowan", "Ryder",
        "Samir", "Sawyer", "Sebastian", "Shane", "Shaun", "Silas", "Solomon", "Spencer",
        "Sterling", "Tanner", "Tariq", "Terrell", "Theo", "Titus", "Tobias", "Trace",
        "Travis", "Trevon", "Tristan", "Tyree", "Vance", "Vaughn", "Victor", "Wade",
        "Walker", "Weston", "Wyatt", "Xavier", "Zachary", "Zane",
    ]

    static let family: [String] = [
        "Abernathy", "Ackerman", "Adkins", "Alderman", "Alston", "Ambrose", "Ashworth",
        "Atwater", "Bagley", "Ballinger", "Bannister", "Barlowe", "Barnhart", "Bascomb",
        "Beauchamp", "Beckwith", "Bellamy", "Benavides", "Bickford", "Birchfield", "Blackmon",
        "Blanchard", "Blakemore", "Bonner", "Boughton", "Bracewell", "Bradshaw", "Bramlett",
        "Bramwell", "Bridgers", "Brigham", "Brockway", "Broussard", "Burkholder", "Burkhart",
        "Cadwell", "Calloway", "Carlisle", "Carrington", "Castellano", "Chadwick", "Chastain",
        "Cheatham", "Clendenin", "Corliss", "Colverson", "Comstock", "Copeland", "Cornish",
        "Coventry", "Cranfield", "Crenshaw", "Crockett", "Cullingworth", "Cutliffe", "Dalrymple",
        "Danforth", "Darrington", "Deitrick", "Delacroix", "Denman", "Devereaux", "Dillard",
        "Dockery", "Donnelly", "Draughn", "Dunleavy", "Eastwick", "Eddings", "Ellsworth",
        "Emberton", "Everly", "Fairbanks", "Falconer", "Farnsworth", "Fenwick", "Ferrell",
        "Fitzhugh", "Fletcher", "Fontaine", "Forsythe", "Fournier", "Gainsford", "Galloway",
        "Garrity", "Gantry", "Gillespie", "Glennon", "Goodloe", "Granville", "Greaves",
        "Grimsley", "Hadley", "Halstead", "Hampshire", "Hargrove", "Harkness", "Hathaway",
        "Havelock", "Hawthorne", "Hendershot", "Hollingsworth", "Holloway", "Huddleston",
        "Idlewild", "Ingersoll", "Ironside", "Jarnigan", "Jessup", "Kellerman", "Kenworthy",
        "Kilgore", "Kingsley", "Kirkpatrick", "Lachlan", "Lamontagne", "Langford", "Larkspur",
        "Lattimore", "Lindhurst", "Lindquist", "Livingston", "Lockridge", "Loveless", "Ludlow",
        "Mabry", "Maddox", "Mancuso", "Marbury", "Marchetti", "Mattingly", "Merriweather",
        "Millgate", "Montague", "Mortenson", "Nesbitt", "Netherton", "Norbury", "Oakhurst",
        "Orrington", "Orsini", "Oversby", "Paddock", "Pemberton", "Pennington", "Petrosky",
        "Pickering", "Pomeroy", "Prescott", "Quarterman", "Radcliffe", "Rasmussen", "Ravenel",
        "Redding", "Renwick", "Ridgeway", "Rockwell", "Rosewood", "Rutherford", "Salisbury",
        "Sandoval", "Satterfield", "Shackleford", "Sheffield", "Shelburne", "Sinclair",
        "Sladen", "Somerville", "Stanbury", "Stanfield", "Stembridge", "Stonebridge",
        "Strickland", "Sutcliffe", "Swinton", "Tarrington", "Thackeray", "Thibodeaux",
        "Threlkeld", "Tolliver", "Trask", "Underwood", "Vandergriff", "Vasquez", "Vermilya",
        "Wainwright", "Wakefield", "Waldrop", "Wardlow", "Weatherby", "Wexler", "Whitfield",
        "Wickersham", "Winsford", "Woodard", "Wrenfield", "Yarborough", "Youngquist",
    ]

    /// Rare, and applied only occasionally.
    static let suffixes: [String] = ["Jr.", "II", "III"]

    /// Surnames that read as a real footballer's rather than as fiction are
    /// deliberately absent. Picking names because they "sound like football
    /// names" is how a generated world ends up feeling like a greatest-hits of
    /// people who actually played, which is precisely what ADR-0005 exists to
    /// prevent. A test also asserts the two pools do not overlap, so nobody is
    /// called Sterling Sterling.
}

/// Parts for inventing colleges.
///
/// Real institutions are as off-limits as real teams, so programmes are built
/// from a place, a kind and occasionally a direction — which also produces the
/// small-school names that make a draft class feel wide.
enum CollegePools {

    static let places: [String] = [
        "Alderwood", "Ashland", "Bayfield", "Belmont", "Bridgewater", "Cascadia", "Cedarcrest",
        "Chandler", "Clearwater", "Coalburg", "Crestline", "Fairhaven", "Fallbrook", "Foxridge",
        "Glenmont", "Granite Bay", "Harbor Point", "Havenwood", "Ironwood", "Kettle Falls",
        "Lakeshore", "Larkfield", "Marbury", "Meridian", "Millbrook", "Northfield", "Oakhollow",
        "Pinehurst", "Quarry Ridge", "Redstone", "Riverbend", "Saltmarsh", "Sandhill",
        "Silverton", "Stonegate", "Sutter Creek", "Thornbury", "Twin Forks", "Vandergrift",
        "Wheatland", "Whitmore", "Willowbank", "Windham", "Yellow Creek",
    ]

    static let kinds: [String] = [
        "State", "University", "Tech", "A&M", "College", "Institute", "Polytechnic",
    ]

    static let directions: [String] = ["North", "South", "East", "West", "Central", "Upper"]
}
