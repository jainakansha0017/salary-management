module Seeds
  # Turns a job level, department and country into a plausible salary.
  #
  # Uniformly random salaries would produce a dashboard where every median is
  # the same and no comparison reveals anything. Pay here is driven by the
  # factors that drive it in reality — level, function and local market — with
  # a right-skewed spread inside each band, so that medians, percentiles and
  # gaps between groups are actually worth looking at.
  module SalaryModel
    # Midpoint of each band in USD, with the share of headcount at that level.
    # Weighted into a pyramid: far more people at L3 than at L8.
    LEVELS = {
      "L1" => { midpoint: 55_000, weight: 8 },
      "L2" => { midpoint: 75_000, weight: 15 },
      "L3" => { midpoint: 95_000, weight: 22 },
      "L4" => { midpoint: 120_000, weight: 20 },
      "L5" => { midpoint: 150_000, weight: 15 },
      "L6" => { midpoint: 190_000, weight: 10 },
      "L7" => { midpoint: 240_000, weight: 7 },
      "L8" => { midpoint: 320_000, weight: 3 }
    }.freeze

    # Function premium — engineering and legal command more than support
    # functions at the same level.
    DEPARTMENT_MULTIPLIER = {
      "Engineering" => 1.15,
      "Data" => 1.12,
      "Legal" => 1.10,
      "Product" => 1.08,
      "Sales" => 1.05,
      "Finance" => 1.00,
      "Design" => 1.00,
      "Marketing" => 0.95,
      "People" => 0.90,
      "Customer Success" => 0.85
    }.freeze

    # Local market rates relative to the US. This is what makes raw local
    # amounts incomparable and the base-currency view necessary.
    COUNTRY_FACTOR = {
      "US" => 1.00,
      "CH" => 1.05,
      "AU" => 0.88,
      "GB" => 0.85,
      "CA" => 0.82,
      "DE" => 0.80,
      "SG" => 0.90,
      "JP" => 0.75,
      "PL" => 0.45,
      "BR" => 0.35,
      "IN" => 0.28
    }.freeze

    DEPARTMENT_ROLE = {
      "Engineering" => "Software Engineer",
      "Data" => "Data Scientist",
      "Product" => "Product Manager",
      "Design" => "Product Designer",
      "Sales" => "Account Executive",
      "Marketing" => "Marketing Manager",
      "Customer Success" => "Customer Success Manager",
      "Finance" => "Financial Analyst",
      "People" => "People Partner",
      "Legal" => "Legal Counsel"
    }.freeze

    LEVEL_TITLE = {
      "L1" => "Associate %<role>s",
      "L2" => "%<role>s",
      "L3" => "Senior %<role>s",
      "L4" => "Staff %<role>s",
      "L5" => "Senior Staff %<role>s",
      "L6" => "Principal %<role>s",
      "L7" => "Director, %<department>s",
      "L8" => "VP, %<department>s"
    }.freeze

    # Standard deviation of the log-normal spread within a band. 0.11 gives a
    # realistic long tail upwards without producing salaries that look absurd.
    SPREAD = 0.11

    module_function

    # Current salary in USD, before any deliberate outlier adjustment.
    def target_usd(level:, department:, country:, rng:)
      midpoint = LEVELS.fetch(level)[:midpoint]
      multiplier = DEPARTMENT_MULTIPLIER.fetch(department)
      factor = COUNTRY_FACTOR.fetch(country)

      # Log-normal rather than uniform: real pay distributions are skewed
      # right, so the mean sits above the median and percentiles differ.
      midpoint * multiplier * factor * Math.exp(gaussian(rng, 0.0, SPREAD))
    end

    def title(level:, department:)
      format(LEVEL_TITLE.fetch(level), role: DEPARTMENT_ROLE.fetch(department), department: department)
    end

    # Box-Muller: turns two uniform draws into one normally distributed value.
    # Written out rather than pulled in as a dependency, since it is four lines
    # and the seed should not need a statistics gem.
    def gaussian(rng, mean, standard_deviation)
      u1 = 1.0 - rng.rand
      u2 = rng.rand

      mean + (standard_deviation * Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2))
    end

    def weighted_pick(rng, weights)
      total = weights.sum { |_, weight| weight }
      target = rng.rand * total

      cumulative = 0.0
      weights.each do |value, weight|
        cumulative += weight
        return value if target < cumulative
      end

      weights.last.first
    end
  end
end
