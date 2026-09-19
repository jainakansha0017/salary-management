module Seeds
  # Region-appropriate names, so a directory filtered to Japan does not come
  # back full of anglophone names.
  #
  # Curated lists rather than a generator gem: the seed must be deterministic
  # and must run in any environment, including the deployed one, so it should
  # not depend on a gem that only exists in development.
  module NamePool
    POOLS = {
      anglo: {
        first: %w[James Olivia Noah Emma Liam Sophia Ethan Ava Mason Isabella Lucas Mia Henry Charlotte Owen Grace],
        last: %w[Smith Johnson Williams Brown Jones Miller Davis Wilson Taylor Clark Walker Hall Young King Wright Baker]
      },
      indian: {
        first: %w[Aarav Ananya Vihaan Diya Arjun Ishita Rohan Kavya Aditya Meera Karthik Priya Rahul Sneha Vikram Nisha],
        last: %w[Sharma Patel Reddy Iyer Nair Gupta Mehta Singh Bose Chauhan Joshi Rao Desai Kulkarni Banerjee Malhotra]
      },
      german: {
        first: %w[Lukas Hannah Felix Lena Jonas Marie Elias Sophie Paul Laura Finn Emilia Leon Clara Moritz Johanna],
        last: %w[Müller Schmidt Schneider Fischer Weber Meyer Wagner Becker Hoffmann Schäfer Koch Richter Klein Wolf Neumann Zimmermann]
      },
      polish: {
        first: %w[Jakub Zofia Kacper Julia Filip Maja Antoni Lena Michał Anna Piotr Katarzyna Tomasz Agnieszka Marcin Ewa],
        last: %w[Nowak Kowalski Wiśniewski Wójcik Kowalczyk Kamiński Lewandowski Zieliński Szymański Woźniak Dąbrowski Kozłowski Mazur Jankowski Krawczyk Piotrowski]
      },
      brazilian: {
        first: %w[Miguel Alice Arthur Helena Gabriel Laura Bernardo Manuela Heitor Valentina Davi Sophia Lucas Isabela Pedro Beatriz],
        last: %w[Silva Santos Oliveira Souza Rodrigues Ferreira Alves Pereira Lima Gomes Costa Ribeiro Martins Carvalho Almeida Barbosa]
      },
      japanese: {
        first: %w[Haruto Sakura Yuto Yui Sota Hina Riku Mei Ren Aoi Kaito Rin Daiki Nanami Takumi Akari],
        last: %w[Sato Suzuki Takahashi Tanaka Watanabe Ito Yamamoto Nakamura Kobayashi Kato Yoshida Yamada Sasaki Matsumoto Inoue Kimura]
      },
      singaporean: {
        first: %w[Wei Jing Kai Mei Jun Ling Hui Xin Zhi Yan Siti Nurul Aisha Farah Ravi Devi],
        last: %w[Tan Lim Lee Ng Wong Chan Goh Koh Teo Ong Chua Yeo Sim Loh Rahman Kumar]
      }
    }.freeze

    COUNTRY_POOL = {
      "US" => :anglo,
      "GB" => :anglo,
      "CA" => :anglo,
      "AU" => :anglo,
      "IN" => :indian,
      "DE" => :german,
      "PL" => :polish,
      "BR" => :brazilian,
      "JP" => :japanese,
      "SG" => :singaporean
    }.freeze

    module_function

    def sample(country:, rng:)
      pool = POOLS.fetch(COUNTRY_POOL.fetch(country))

      [ pool[:first].sample(random: rng), pool[:last].sample(random: rng) ]
    end
  end
end
