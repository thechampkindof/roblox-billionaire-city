# Billionaire City Tycoon — Game Design Document

> Source of truth for design. Reproduced verbatim from the design brief (Appendix A), with
> engineering follow-ups tracked in [`ARCHITECTURE.md`](./ARCHITECTURE.md) and open questions in
> [`DECISIONS.md`](./DECISIONS.md).

# Appendix A · Game Design Document

**Hard rules:** one enormous city. Hundreds of meaningful upgrades. A long-term goal of building and maxing out everything. No global expansion, no separate worlds, no forced rebirths. The grind comes from having lots of meaningful things to complete, not from making every purchase ridiculously expensive.

**Design pillars**

1. Always something worth buying: short, medium and long goals coexist.
2. Progress you can see: the city visibly grows.
3. One city, no resets: Legacy milestones never wipe anything.
4. The grind is breadth, not price.
5. Fair free-to-play: completion never requires Robux.
6. Mobile-first clarity: uncluttered HUD, big touch targets.
7. Server authority and safe saves.

## A1 · Concept and arc

- Tycoon + simulator + city management + collection. Each player develops a persistent city plot in a shared server. Designed for 100–200+ hours of completionist play, subject to balancing.
- Start: a broke entrepreneur with **$500**, a small plot and one basic business.
- Early game: hands-on (collect money, buy equipment, serve customers, small improvements). Midgame: several businesses, whole districts, automated income. Endgame: expensive megaprojects, building mastery, rare vehicles, finishing the entire upgrade tree.
- The goal is not merely $1B. It is an interconnected city where every business, road, building and upgrade contributes to the empire.

## A2 · Map and plots

- One continuous persistent city with eight districts connected by roads and public transit. Each player owns a personal city plot; purchases, upgrades, decorations and vehicles are saved to their profile.
- Player-owned areas: land the player builds on. Shared areas: public roads, plazas, leaderboards and social spaces where players meet, visit each other and join city events.
- Land is divided into parcels. Each has a price, a size, a permitted building type and optionally a population or development requirement. Some parcels are reserved for large projects (stadium, skyscrapers). Unlock parcels with cash plus milestones.
- Construction: select a property, pay its cost, watch a progress bar. Small builds finish quickly; landmarks need several stages and extra investment. Players keep earning during construction. Build times create anticipation and never force unreasonable offline waits.
- The city visibly improves: empty lots become construction sites, small stores become larger businesses, roads, streetlights, vehicles and trees fill in. Players must see progress beyond the money counter.

## A3 · Economy

| Currency | Role | Earned from |
|---|---|---|
| **Cash** | Primary. Land, buildings, workers, vehicles, most upgrades. | Business profits, customer transactions, contracts, activities |
| **Prestige Points (PP)** | Permanent progression. Special building styles, advanced research, optional cosmetics. | Major milestones, maxing selected properties, high city ratings |
| **Reputation** | Measure of business success. Unlocks exclusive contracts, premium businesses, elite property opportunities. | Customer satisfaction, successful contracts, city development |
| **Research Points** | Fuel for the research tree (some nodes also cost cash). | Contracts, district milestones, mastery |

PP and Reputation never replace Cash.

- **Income:** each business earns from its level, customer demand, staff efficiency, upgrades and operating expenses. Revenue = customer traffic × average spend, limited by service capacity. Costs = wages, supplies, utilities, maintenance. The UI shows estimated income per minute, operating costs and net profit **before** the player buys expensive upgrades.
- **Active vs passive:** active income = contracts, manual service, deliveries, events. Passive = owned businesses and automation. Early players interact often; managers, equipment and automation later remove constant clicking.
- **Offline income** is capped and computed from the last saved timestamp (a few hours). It gives casual players a reason to return without trivializing the game.
- **Scaling:** upgrade cost rises by a percentage per level; income growth is designer-controlled. No single early upgrade may fund every later building. Prices, income and effects are tested together. Milestones, contracts and new mechanics carry progress when the next purchase is expensive. Numbers go from thousands to millions, billions and far beyond, always readable.

## A4 · The eight districts

All eight stay part of the same city. Each has its own buildings, upgrade paths, challenges, visual identity and unlock conditions.

| District | Buildings | Core mechanics | Completion goal |
|---|---|---|---|
| **D1 Starter** (everyone begins here) | Convenience store, gas station, small restaurant, starter houses, small apartment building, parking lot, car wash, small office, mini-market | Teaches buy → install equipment → hire workers → serve customers → collect income. Cheap purchases. Finishing the early tree unlocks better staff, business management, larger parcels and the Shopping District. Stays useful all game. | Fully upgrade every starter business, fill all parcels, unlock every property variation, max development rating |
| **D2 Shopping** | Clothing stores, electronics stores, supermarket, restaurants and cafés, cinema, shopping mall, furniture store, luxury boutiques, large department store | Traffic and retail demand. Each store sells products to a customer type. Upgrade product quality, inventory capacity, cashiers, premium products, floor space. The **mall** is a multistage megaproject: small retail complex → large destination with multiple stores, restaurants, entertainment and premium facilities. | Max every store, unlock every product category, finish all mall phases, max retail demand |
| **D3 Financial** | Office buildings, bank, corporate HQ, business center, stock exchange, insurance company, high-rise offices, signature skyscraper | Offices earn tenant revenue; upgrade floors, office quality, leases, building services, managers. The bank adds **investments**: fictional, in-game currency only, different returns and risk levels, clearly explained, never real-money gambling. Corporate HQ unlocks company-wide upgrades affecting many businesses at once. | Fill every office floor, max all financial properties, complete corporate research, build the signature skyscraper |
| **D4 Luxury** | Luxury homes, mansions, penthouse apartments, luxury car dealership, private club, high-end hotel, luxury condo towers, waterfront estates | Properties have a base value and a quality rating; upgrade interiors, landscaping, security, pools, garages, amenities. Some are personal homes, others are rentals or hotels that earn income. Personal homes have interactive interiors, furniture collections, display rooms and vehicle garages. | Own every luxury property, unlock all interior themes, collect rare furniture, max every property's value and amenities |
| **D5 Entertainment** | Football stadium, concert arena, amusement park, convention center, large cinema complex, hotels, event plaza, indoor entertainment center | Event-driven income. The stadium hosts fictional sporting events, the arena hosts concerts, the park attracts visitors; each event needs preparation and gives a temporary traffic spike. Upgrade seating, food stalls, security, parking, event quality, ticketing. Events can be server-wide or triggered by a player's upgrades; participation is optional and rewards are never required for normal progress. | Max every venue, unlock all event types, reach max capacity, collect every event trophy |
| **D6 Industrial** | Warehouse, manufacturing factory, packaging plant, distribution center, research facility, automated production line, recycling center, large industrial complex | Supply chains: factories turn raw materials into goods, warehouses store them, distribution centers deliver to shops (e.g. factory electronics → warehouse → Shopping District electronics store). Better chains cut costs, improve availability, raise profit. Start manual, then automate with conveyors, robotic arms, inventory systems, logistics managers. A missing supply never shuts down the empire: businesses fall back to a less profitable source. | Max all factories, unlock every production recipe, automate every eligible chain, complete all industrial research |
| **D7 Transportation** | Parking garages, public bus depot, subway stations, train station, highway network, airport terminal, private aviation terminal, vehicle service centers | Transport capacity shapes customer movement and demand: better roads reduce congestion, public transit raises access to commercial areas, garages support big destinations. The **airport is a late-game megaproject** (passenger income, tourism events), not a gateway to other playable cities. Upgrade road sections, transit capacity, traffic signals, services. | Build the whole network, unlock every transit upgrade, maximize capacity, connect every district to the main transport system |
| **D8 Billionaire** (final, most expensive) | Signature mega-skyscraper, billionaire HQ, luxury hotel tower, landmark observation tower, exclusive shopping complex, premium residential tower, grand city plaza, hidden landmark property | Long construction chains: land acquisition → foundations → structure → utilities → interior fit-out → final certification. Each phase costs money and needs earlier milestones; completing one changes the building's appearance and may unlock floors, amenities or business functions. Some landmark upgrades also cost PP. Must feel like a reward for the whole game. | Finish every phase, max every building, unlock all landmark appearances, complete the final city-development milestones |

## A5 · Upgrades and mastery

- **Six upgrade categories** per major property: *Construction* (size, floors, rooms, exterior), *Staffing* (employees, managers, speed, efficiency), *Equipment* (production speed, customer capacity, storage, automation), *Business* (marketing, product quality, demand, margins), *Appearance* (themes, signs, lighting, furniture, landscaping, effects), *Mastery* (permanent bonuses, cosmetics, unique rewards).
- **Mastery level 1–100 per property.** XP comes from normal operation, property objectives and upgrade spending, with an earning cap or diminishing returns so a cheap business left idle cannot max everything. Milestones unlock construction styles, specialized equipment, extra capacity and permanent income bonuses. Level 100 = fully mastered (unique appearance, special ability or city-wide bonus).
- Upgrade trees differ by building type (restaurant: recipes, kitchen, seating, staff, service quality; factory: machinery, speed, storage, robotics).
- **Levels** improve an operating property. **Construction phases** physically expand or transform a major building. **Mastery** rewards long-term investment. **Cosmetics** change appearance without necessarily affecting income.

## A6 · Core loop

Collect income → choose an investment (upgrade, hire, save for a building) → improve the city → unlock content (cash, reputation, property, district gates) → repeat at larger scale. Short-, medium- and long-term goals are always available together (better cash register / finish the mall / the signature skyscraper), so a player who cannot afford the big project still has worthwhile progress.

## A7 · Employees, managers, automation

- Each business has limited employee slots; upgrades add slots, capacity and advanced roles. Grades: **Basic, Skilled, Expert, Executive** (higher grades cost more to hire and maintain but are more efficient). Players do not hire thousands of NPCs by hand: staff are managed through a clean UI with visible staff in the world.
- **Managers** unlock at a business-level threshold and automate routine operations: staffing assignments, restocking, collecting revenue into the player's account. A basic manager handles one store; an advanced manager supervises an entire complex. Early businesses need attention; later ones become automated components of a larger empire.

## A8 · Customers, population, happiness

- NPC customers have needs and preferences (food, shopping, entertainment, luxury). Traffic depends on: building quality and services, product selection and pricing, road access and parking, public transit, marketing and reputation, events and tourism, overall city development. A poorly connected mall earns less than a well-connected one.
- **Population** is an abstract statistic from residential buildings; milestones unlock rewards. It is not a promise of thousands of rendered characters.
- **Happiness score** from: housing and essential services, traffic congestion, cleanliness and maintenance, parks and public spaces, entertainment, safety and infrastructure. High happiness raises reputation and demand. Low happiness reduces some bonuses but **never destroys income or removes buildings**.

## A9 · Roads, infrastructure, services

- **Roads and traffic:** wider streets, better intersections, traffic lights, decorative roads, highways. A manageable number of active vehicles plus abstracted traffic for distant streets. Congestion reduces efficiency of affected commercial areas.
- **Utilities:** electricity (advanced machinery, larger buildings), water (residences, restaurants, hotels, landscaping), waste (cleanliness, population growth), maintenance (fewer failures, less deterioration). Simple at first, deeper later. City-wide upgrades improve several buildings; individual facilities can be upgraded for capacity.
- **Parks and public facilities:** parks, plazas, fountains, schools, hospitals. Little direct income; they raise happiness, population capacity, reputation and development milestones. A real tradeoff against profitable buildings.

## A10 · Cars, garages, collecting

- Categories: starter cars, sedans and SUVs, sports cars, supercars, hypercars, luxury limousines, collectible concept cars, rare event vehicles. Bought from dealerships with in-game money; each has a price, performance stats and customization.
- Upgrades: acceleration, top speed, handling, braking, appearance. Cosmetics: paint, rims, spoilers, lighting. Higher tiers cost more and may have unlock requirements.
- Home garages and display areas can be upgraded; special garages unlock at milestones. A collection menu tracks every vehicle ever owned; collecting categories or sets grants rewards.
- Vehicles are fun to drive but **never mandatory** for making money.

## A11 · Houses, interiors

- Each residential property has a cost, exterior style, interior layout and customization options. Players start with a basic home and unlock larger ones as net worth and development grow: starter homes and apartments → luxury mansions, penthouses, waterfront estates.
- Interior upgrades: furniture sets, bedroom and kitchen, home theater, gaming room, swimming pool, office/study, display cabinets, smart-home systems, lighting and wall themes, garage expansion. Some are purely cosmetic; others unlock extra vehicle storage or property value bonuses.
- Players save room layouts and pick unlocked themes. Furniture rarity: common, premium, rare. Each player's home should feel different even from the same base house.

## A12 · Contracts, missions, events

- **Business contracts** from businesses and NPC clients: deliver a quantity of goods, hit a customer satisfaction target, upgrade a property to a level, generate target revenue, complete a construction phase, improve transport access to a district. Rewards: cash, Reputation, mastery XP, special blueprints.
- **Major construction contracts:** longer objectives tied to large buildings (materials, cash, prerequisites, multiple stages) with a dedicated progress UI.
- **City events:** tourism boom (entertainment traffic), retail festival (shopping demand), business expo (corporate contracts), construction week (construction discounts), city anniversary (exclusive decorations). Cooldowns, clear durations, fair rewards. Never force players to be online at a specific time to avoid missing permanent content.

## A13 · Research

Research points come from contracts, district milestones and mastery; some nodes also cost cash. Five branches:

- **Industrial Technology:** robotics, advanced machinery, cheaper production, faster logistics.
- **Architecture:** additional building levels, premium construction materials, signature skyscraper designs.
- **Transportation:** traffic capacity, public transit, parking, delivery efficiency.
- **Business Management:** employee efficiency, marketing, profit margins, manager capabilities.
- **Urban Development:** happiness, public services, population capacity, city reputation.

The order is a strategic choice, and the entire tree is eventually completable.

## A14 · Unlock requirements

Districts never unlock on money alone. Combine financial progress, development and earlier achievements. `[ASSUMPTION]` Initial balancing targets (all tunable; the original table did not survive, so these are proposals):

| # | District | Net worth | Other gates (all required) | Target arrival (active hours) |
|---|---|---|---|---|
| 1 | Starter | none | none | 0 |
| 2 | Shopping | $25K | Starter ≥ 40% complete; 3 businesses with managers | 2–4 |
| 3 | Financial | $1M | Shopping ≥ 35%; Reputation ≥ 250 | 8–14 |
| 4 | Luxury | $25M | Financial ≥ 30%; Population ≥ 5,000 | 22–32 |
| 5 | Entertainment | $250M | Shopping ≥ 60%; Luxury ≥ 25%; Happiness ≥ 60 | 40–55 |
| 6 | Industrial | $2.5B | Financial ≥ 50%; Industrial Technology I; Population ≥ 25,000 | 60–80 |
| 7 | Transportation | $25B | Industrial ≥ 35%; Entertainment ≥ 35%; Transportation II | 80–105 |
| 8 | Billionaire | $250B | 6 of 7 districts ≥ 60%; Legacy "Billionaire" and "Corporate Executive"; PP ≥ 100 | 105–135 |

Even after a district opens, individual buildings may require a district level, research, population, Reputation or a completed contract (e.g. Financial District open, but the office tower's foundation project must finish before its upper floors).

Seven progression layers: **unlock district → purchase land → unlock blueprint → complete construction → upgrade → max mastery → finish collection and cosmetic rewards.**

## A15 · Achievements, collections, completion

- Categories: Wealth, Construction, Business, Infrastructure, Collections, Social, Mastery, Secrets. Rewards: cash, PP, titles, decorations, exclusive building skins.
- **Completion menu** (one of the most important screens): % buildings unlocked, % properties fully upgraded, district completion %, total building mastery, research completion, vehicle collection, house customization, achievement completion, secret discoveries, **total City Completion %**. A player can have 75% of buildings unlocked but only 40% of the game complete.
- **100% City Completion** = all launch-content buildings, all required upgrade trees, all research, all standard collections, all core achievements. Optional limited-time event cosmetics are excluded, so missing an event never blocks completion.

## A16 · Legacy: prestige without resetting

No rebirths. Legacy milestones are earned by net worth targets, completing districts or finishing large projects: **First Millionaire, Major Investor, Real Estate Mogul, Corporate Executive, Billionaire, City Architect, Legendary Developer.** Each awards PP, titles and sometimes permanent city-wide bonuses. Buildings, money, vehicles and district progress are never wiped. PP unlock special research and cosmetics; ordinary progress never requires resets.

`[ASSUMPTION]` Criteria: First Millionaire = net worth $1M. Major Investor = lifetime investment profit $10M. Real Estate Mogul = own 100 parcels. Corporate Executive = Corporate HQ built and Business Management research tier III done. Billionaire = net worth $1B. City Architect = 4 districts at 100% development. Legendary Developer = 100% City Completion.

## A17 · Multiplayer and social

- **Visiting:** players visit friends' cities, explore completed buildings, view collections and designs. The owner chooses whether visitors can enter homes, drive display vehicles or interact with selected areas. Visitors cannot take money, damage buildings or remove properties.
- **Leaderboards (separate boards):** highest net worth, highest hourly profit, most developed city, most mastered buildings, most completed collections, highest city rating, most achievements.
- **Cooperative:** shared construction events, city tours, cooperative missions (e.g. a server-wide project; rewards by participation).
- **Trading** (if included): eligible cosmetics, vehicle skins, decorations and other nonessential collectibles only. Core businesses, buildings and permanent progression are never transferable.

## A18 · Dailies, weeklies, milestones

Daily examples: collect profits from five businesses, upgrade a building three times, complete a delivery contract, drive a certain distance, improve a property's customer rating (rewards: cash, research points, mastery XP). Weekly: multi-district goals such as completing a construction phase, generating target profit, mastering a building category. Milestone rewards for big achievements (finishing a district: landmark skin, special vehicle, permanent bonus). All supplementary: ignoring them must never block full completion.

## A19 · Randomness and rare collectibles

Rare vehicle paint finishes, limited building skins, special office furniture, unique street decorations, hidden construction blueprints, trophy displays, rare home interior sets. Found through exploration, achievements and hard challenges. Randomness never gates essential progression; disclose odds for any randomized reward; rare cosmetics give no overwhelming income advantage; important gameplay unlocks always have a deterministic route. Hidden building example: find three clues across the city, solve a puzzle, then pay for construction.

## A20 · UI and menus

- **HUD:** cash, net worth, income per minute, city rating, current objective, construction notifications, quick access to buildings and the map. Uncluttered, especially on mobile.
- **City management menu:** which businesses are profitable, which buildings need upgrades, income by district, projects under construction.
- **Building interface tabs:** Overview, Upgrades, Staff, Income & Expenses, Construction, Mastery, Customization. Every upgrade shows cost, prerequisites, expected effect and current level **before** purchase.
- **Map and objective tracker:** owned buildings, locked properties, construction sites, objectives. Players pin a goal (e.g. the skyscraper or a vehicle) and see remaining requirements.
- **Mobile:** touch controls, scalable menus, readable text, simple driving controls. No tiny buttons, no hover-only interactions.

## A21 · Saving and player data

Profile stores: Cash, Reputation, PP, net worth; purchased land and completed construction phases; building levels, upgrades, mastery XP; employee assignments and manager upgrades; district unlocks and development ratings; research progress and completed contracts; vehicles, houses, furniture and cosmetic collections; achievements, Legacy milestones, completion %; current construction projects and their progress. Save periodically and after significant changes (land purchase, major building completed, district unlock); handle server shutdowns and failed saves. The server verifies purchases, calculates earnings and approves progression. Players never lose a city by leaving or disconnecting; the profile loads intact into a new server.

## A22 · Performance

Businesses compute income on the server at controlled intervals (no heavy per-machine scripts). Only nearby customers get detailed movement; distant customers use simplified population and traffic math. Distant buildings use lower detail; complex interiors load only when needed. Distant traffic is statistical. Purchases, inventory, income and progression are validated server-side. Systems are separate modules with clear interfaces. Profiles carry a version number so updates can safely add fields. A city with hundreds of properties must stay playable on phones and tablets.

## A23 · Monetization

Optional purchases only. Permanent buildings, essential district unlocks and core research stay achievable through normal play. Sell customization and convenience, not the intended 100-hour progression. No pay-to-win exclusive income systems that leave free players permanently inferior; any paid multipliers are carefully balanced.

## A24 · Endgame

The endgame is completing the city, not reaching a cash figure. Reaching the Billionaire District unlocks the final major district but leaves plenty to do: finish every phase of the signature skyscraper; mastery 100 on every eligible building; every research branch; max all eight district development trees; buy every standard property and parcel; collect every standard vehicle and house customization set; all permanent achievements and hidden discoveries; max transportation, utilities and public services; highest city rating; **100% City Completion.** Afterwards: optional cosmetics, city design, leaderboards, future content updates. The game has an actual completion target rather than ever-inflating prices.

---
---


