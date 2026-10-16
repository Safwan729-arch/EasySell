-- =============================================================================
-- EasySell demo data. Paste into the Supabase SQL editor and Run. Run ONCE:
-- a second run stops with "Demo data is already in ...".
-- Needs every migration up to 0018 (payment_method).
--
-- It fills the MOST RECENTLY CREATED shop. To pick another one, change the
-- `select ... from shops` line below (e.g. add `where name = 'My Shop'`).
--
-- What you get:
--   * 55 grocery products across every default category, Taka prices; a few
--     loose items sold by kg/litre; Nescafe out of stock
--   * 5 weeks of sales (cash / digital / credit, a few discounts, some voice
--     and photo-scan entries), so Home, Reports and History have numbers
--   * a restock two weeks ago, so the Restock planner has a real speed;
--     Pepsi and Teer oil are nearly out -> "Buy now"
--   * an expiry date on all 39 packaged products (loose rice, dal, vegetables,
--     sugar, palm oil have none). Most are months away; milk, yogurt, eggs,
--     fruit cake, Mojo and garam masala expire within days; 3 loaves of bread
--     and 5 Dairy Milk bars have already expired -> expiry alerts on Home
--   * 4 khata customers with debts and part-payments
-- Remove it again with supabase/seed/remove_demo_data.sql.
-- =============================================================================
do $$
declare
  v_shop      uuid;
  v_shop_name text;
  v_today     date := (now() at time zone 'Asia/Dhaka')::date;
  v_day       date;
  v_receipts  int;
  v_ts        timestamptz;
  v_group     uuid;
  v_r         double precision;
  v_method    text;
  v_customer  uuid;
  v_source    text;
  v_discount  numeric;
  v_first     boolean;
  v_total     numeric;
  v_line      record;
  v_qty       numeric;
  v_restock   timestamptz := ((v_today - 14) + time '09:30') at time zone 'Asia/Dhaka';
  v_sold      numeric;
  v_p         record;
  v_c         record;
  v_balance   numeric;
begin
  perform setseed(0.42); -- the same "random" data every time

  select id, name into v_shop, v_shop_name
    from shops order by created_at desc limit 1;
  if v_shop is null then
    raise exception 'No shop found. Sign up in the app and create a shop first.';
  end if;
  if exists (select 1 from products
               where shop_id = v_shop and name = 'Pepsi' and brand = 'PepsiCo') then
    raise exception 'Demo data is already in "%".', v_shop_name;
  end if;

  -- ---------------------------------------------------------------------------
  -- Products. stock = what is on the shelf NOW; w = how often it sells;
  -- qmin/qmax = how many one customer buys (kg items in half-kilo steps).
  -- ---------------------------------------------------------------------------
  create temp table _demo (
    pid uuid default gen_random_uuid(),
    name text, brand text, variant text, cat text,
    unit_type text, unit text,
    buy numeric, sell numeric, stock numeric, reorder numeric,
    w numeric, qmin numeric, qmax numeric
  ) on commit drop;

  insert into _demo (name, brand, variant, cat, unit_type, unit, buy, sell, stock, reorder, w, qmin, qmax) values
    -- Rice & grains
    ('Miniket Rice',     'Loose',      null,     'Rice & grains',        'weight', 'kg',    68,  75,  42, 20, 9, 1, 5),
    ('Nazirshail Rice',  'Loose',      null,     'Rice & grains',        'weight', 'kg',    72,  80,  35, 15, 5, 1, 5),
    ('Chinigura Rice',   'Pran',       '1kg',    'Rice & grains',        'piece',  'pcs',  150, 165,  14,  5, 3, 1, 2),
    ('Atta',             'Fresh',      '2kg',    'Rice & grains',        'piece',  'pcs',  120, 130,  16,  6, 4, 1, 2),
    ('Suji',             'Teer',       '500g',   'Rice & grains',        'piece',  'pcs',   45,  55,  12,  4, 2, 1, 1),
    ('Chira',            'Loose',      null,     'Rice & grains',        'weight', 'kg',    70,  80,  10,  4, 2, 0.5, 1),
    -- Cooking oil
    ('Soyabean Oil',     'Teer',       '1L',     'Cooking oil',          'piece',  'pcs',  178, 190,   2,  6, 6, 1, 2),
    ('Soyabean Oil',     'Rupchanda',  '5L',     'Cooking oil',          'piece',  'pcs',  860, 905,   7,  2, 2, 1, 1),
    ('Mustard Oil',      'Radhuni',    '500ml',  'Cooking oil',          'piece',  'pcs',  160, 175,  10,  4, 3, 1, 1),
    ('Palm Oil',         'Loose',      null,     'Cooking oil',          'volume', 'litre',150, 165,  12,  5, 2, 1, 2),
    -- Pulses/lentils
    ('Masoor Dal',       'Loose',      null,     'Pulses/lentils',       'weight', 'kg',   105, 120,  25, 10, 5, 0.5, 2),
    ('Mung Dal',         'Loose',      null,     'Pulses/lentils',       'weight', 'kg',   140, 160,  12,  5, 3, 0.5, 2),
    ('Chola',            'Loose',      null,     'Pulses/lentils',       'weight', 'kg',    95, 110,  15,  5, 2, 0.5, 2),
    ('Mashkalai Dal',    'Loose',      null,     'Pulses/lentils',       'weight', 'kg',   150, 170,   8,  3, 1, 0.5, 1),
    -- Vegetables
    ('Onion',            'Local',      null,     'Vegetables',           'weight', 'kg',    55,  65,  30, 15, 8, 1, 3),
    ('Potato',           'Local',      null,     'Vegetables',           'weight', 'kg',    25,  32,  55, 20, 7, 1, 5),
    ('Garlic',           'Local',      null,     'Vegetables',           'weight', 'kg',   180, 220,   8,  3, 4, 0.5, 1),
    ('Ginger',           'Local',      null,     'Vegetables',           'weight', 'kg',   200, 240,   6,  2, 3, 0.5, 1),
    ('Green Chilli',     'Local',      null,     'Vegetables',           'weight', 'kg',   100, 140,   4,  2, 4, 0.5, 1),
    ('Tomato',           'Local',      null,     'Vegetables',           'weight', 'kg',    60,  80,  10,  4, 4, 0.5, 2),
    -- Spices
    ('Turmeric Powder',  'Radhuni',    '200g',   'Spices',               'piece',  'pcs',   70,  80,  15,  5, 2, 1, 1),
    ('Chilli Powder',    'Radhuni',    '200g',   'Spices',               'piece',  'pcs',   75,  85,  14,  5, 2, 1, 1),
    ('Cumin Powder',     'Radhuni',    '100g',   'Spices',               'piece',  'pcs',   85,  95,  10,  4, 1, 1, 1),
    ('Garam Masala',     'Radhuni',    '50g',    'Spices',               'piece',  'pcs',   60,  70,   8,  3, 1, 1, 1),
    ('Salt',             'ACI',        '1kg',    'Spices',               'piece',  'pcs',   38,  42,  40, 12, 6, 1, 2),
    ('Sugar',            'Loose',      null,     null,                   'weight', 'kg',   120, 135,  30, 10, 6, 1, 2),
    -- Cleaning & detergent
    ('Wheel Powder',     'Unilever',   '1kg',    'Cleaning & detergent', 'piece',  'pcs',  120, 135,   9,  4, 3, 1, 1),
    ('Rin Powder',       'Unilever',   '500g',   'Cleaning & detergent', 'piece',  'pcs',   75,  85,  10,  4, 2, 1, 1),
    ('Vim Bar',          'Unilever',   '300g',   'Cleaning & detergent', 'piece',  'pcs',   32,  38,  20,  6, 3, 1, 2),
    ('Harpic',           'Reckitt',    '500ml',  'Cleaning & detergent', 'piece',  'pcs',  140, 155,   6,  2, 1, 1, 1),
    -- Personal care
    ('Lux Soap',         'Unilever',   '100g',   'Personal care',        'piece',  'pcs',   52,  60,  22,  6, 4, 1, 2),
    ('Lifebuoy Soap',    'Unilever',   '100g',   'Personal care',        'piece',  'pcs',   48,  55,  25,  8, 4, 1, 2),
    ('Sunsilk Shampoo',  'Unilever',   '180ml',  'Personal care',        'piece',  'pcs',  220, 245,   8,  3, 1, 1, 1),
    ('Toothpaste',       'Pepsodent',  '100g',   'Personal care',        'piece',  'pcs',   85,  95,  14,  5, 2, 1, 1),
    ('Coconut Oil',      'Parachute',  '200ml',  'Personal care',        'piece',  'pcs',  140, 155,  10,  4, 2, 1, 1),
    -- Beverages
    ('Pepsi',            'PepsiCo',    '500ml',  'Beverages',            'piece',  'pcs',   32,  40,   3, 12, 9, 1, 4),
    ('Mojo',             'Akij',       '250ml',  'Beverages',            'piece',  'pcs',   18,  25,  40, 10, 5, 1, 4),
    ('Coca-Cola',        'Coca-Cola',  '1L',     'Beverages',            'piece',  'pcs',   70,  80,  12,  6, 4, 1, 2),
    ('Sprite',           'Coca-Cola',  '250ml',  'Beverages',            'piece',  'pcs',   22,  25,  30, 10, 3, 1, 3),
    ('Mum Water',        'Partex',     '500ml',  'Beverages',            'piece',  'pcs',   12,  15,  48, 24, 7, 1, 3),
    ('Tea',              'Ispahani',   '400g',   'Beverages',            'piece',  'pcs',  230, 255,   9,  3, 2, 1, 1),
    ('Nescafe Classic',  'Nestle',     '50g',    'Beverages',            'piece',  'pcs',  260, 290,   0,  2, 1, 1, 1),
    -- Snacks
    ('Potato Crackers',  'Bombay',     '22g',    'Snacks',               'piece',  'pcs',    8,  10,  60, 20, 6, 1, 5),
    ('Chanachur',        'Bombay',     '150g',   'Snacks',               'piece',  'pcs',   45,  50,  20,  6, 4, 1, 2),
    ('Mr. Noodles',      'Square',     'Masala', 'Snacks',               'piece',  'pcs',   18,  20,  50, 20, 5, 1, 4),
    ('Energy Plus',      'Olympic',    '240g',   'Snacks',               'piece',  'pcs',   35,  40,  18,  6, 4, 1, 2),
    ('Dairy Milk',       'Cadbury',    '38g',    'Snacks',               'piece',  'pcs',   75,  85,  15,  5, 2, 1, 2),
    ('Fruit Cake',       'Bisk Club',  '300g',   'Snacks',               'piece',  'pcs',  110, 125,   6,  2, 1, 1, 1),
    ('Sandwich Bread',   'Fresh Bake', '400g',   'Snacks',               'piece',  'pcs',   45,  55,   8,  4, 5, 1, 1),
    -- Dairy
    ('Liquid Milk',      'Milk Vita',  '500ml',  'Dairy',                'piece',  'pcs',   42,  50,  10,  6, 6, 1, 2),
    ('Sweet Yogurt',     'Pran',       '500g',   'Dairy',                'piece',  'pcs',   70,  85,   5,  3, 2, 1, 1),
    ('Farm Eggs',        'Local',      null,     'Dairy',                'piece',  'pcs',   12,  14,  90, 30, 7, 2, 12),
    ('Milk Powder',      'Dano',       '500g',   'Dairy',                'piece',  'pcs',  400, 440,   7,  3, 2, 1, 1),
    ('Butter',           'Aarong',     '200g',   'Dairy',                'piece',  'pcs',  230, 255,   4,  2, 1, 1, 1),
    ('Ghee',             'Pran',       '200g',   'Dairy',                'piece',  'pcs',  290, 320,   5,  2, 1, 1, 1);

  -- created 40 days ago: the restock planner ignores days before a product
  -- existed, and every sale below is newer than that.
  insert into products (id, shop_id, name, brand, variant, category, category_id,
                        unit_type, unit, quantity, buying_price, selling_price,
                        reorder_threshold, created_at, updated_at)
  select d.pid, v_shop, d.name, d.brand, d.variant, d.cat,
         (select c.id from categories c
            where c.shop_id = v_shop and c.name_normalized = lower(d.cat)),
         d.unit_type, d.unit, d.stock, d.buy, d.sell, d.reorder,
         now() - interval '40 days', now()
  from _demo d;

  -- ---------------------------------------------------------------------------
  -- Khata customers
  -- ---------------------------------------------------------------------------
  insert into customers (shop_id, name, phone, note, created_at) values
    (v_shop, 'Rahim Uddin',    '01711-234567', 'Demo customer', now() - interval '40 days'),
    (v_shop, 'Karim Mia',      '01819-876543', 'Demo customer', now() - interval '40 days'),
    (v_shop, 'Fatema Begum',   '01912-345678', 'Demo customer', now() - interval '40 days'),
    (v_shop, 'Shahana Akter',  '01556-112233', 'Demo customer', now() - interval '40 days');

  -- ---------------------------------------------------------------------------
  -- Sales: 35 days up to now, 5-9 receipts a day (Fridays busier), shop hours
  -- 8 AM - 9 PM Dhaka time. Prices are frozen on each row as the app does.
  -- ---------------------------------------------------------------------------
  for v_day in select generate_series(v_today - 35, v_today, interval '1 day')::date loop
    v_receipts := 5 + floor(random() * 5)::int
                  + case when extract(isodow from v_day) = 5 then 3 else 0 end;

    for i in 1..v_receipts loop
      v_ts := (v_day + time '08:00' + random() * interval '13 hours')
                at time zone 'Asia/Dhaka';
      continue when v_ts > now(); -- today: only sales that already happened

      v_group := gen_random_uuid();
      v_r := random();
      v_method   := case when v_r < 0.55 then 'cash' when v_r < 0.85 then 'digital' else 'credit' end;
      v_customer := case when v_method = 'credit'
                      then (select id from customers
                              where shop_id = v_shop and note = 'Demo customer'
                              order by random() limit 1)
                    end;
      v_r := random();
      v_source := case when v_r < 0.70 then 'manual' when v_r < 0.88 then 'voice' else 'image' end;
      v_discount := case when random() < 0.10 then 5 + floor(random() * 16) else 0 end;
      v_first := true;
      v_total := 0;

      -- 1-3 different products, popular ones more often (weighted sampling).
      for v_line in
        select * from _demo
          order by power(random(), 1.0 / w) desc
          limit 1 + floor(random() * 3)::int
      loop
        if v_line.unit_type in ('weight', 'volume') then
          v_qty := greatest(0.5, round((v_line.qmin + random() * (v_line.qmax - v_line.qmin)) * 2) / 2);
        else
          v_qty := floor(v_line.qmin + random() * (v_line.qmax - v_line.qmin + 1));
          if v_line.name = 'Farm Eggs' then v_qty := v_qty - mod(v_qty, 2); end if;
        end if;

        insert into transactions (shop_id, product_id, type, quantity, buying_price,
                                  selling_price, source, sale_group_id,
                                  discount_amount, payment_method, created_at)
        values (v_shop, v_line.pid, 'sale', v_qty, v_line.buy, v_line.sell,
                v_source, v_group,
                case when v_first then least(v_discount, floor(v_line.sell * v_qty)) else 0 end,
                v_method, v_ts);

        v_total := v_total + v_line.sell * v_qty
                   - case when v_first then least(v_discount, floor(v_line.sell * v_qty)) else 0 end;
        v_first := false;
      end loop;

      if v_customer is not null and round(v_total, 2) > 0 then
        insert into customer_ledger (shop_id, customer_id, entry_type, amount,
                                     sale_group_id, created_at)
        values (v_shop, v_customer, 'credit_sale', round(v_total, 2), v_group, v_ts);
      end if;
    end loop;
  end loop;

  -- ---------------------------------------------------------------------------
  -- One restock 14 days ago: 80% of what has sold since. The planner rebuilds
  -- past stock backwards from today's stock, so this keeps it above zero.
  -- ---------------------------------------------------------------------------
  for v_p in select * from _demo loop
    select coalesce(sum(quantity), 0) into v_sold
      from transactions
      where product_id = v_p.pid and type = 'sale' and created_at >= v_restock;
    if round(v_sold * 0.8) >= 1 then
      insert into transactions (shop_id, product_id, type, quantity, buying_price,
                                selling_price, source, payment_method, created_at)
      values (v_shop, v_p.pid, 'restock', round(v_sold * 0.8), v_p.buy, v_p.sell,
              'manual', null, v_restock);
    end if;
  end loop;

  -- ---------------------------------------------------------------------------
  -- Deliveries with expiry dates: every packaged product. Loose rice, dal,
  -- vegetables, sugar and palm oil have none, like in a real shop.
  --   ago   = received this many days before today
  --   shelf = shelf life in days, so expiry = received + shelf
  -- Each product's deliveries add up to its stock exactly, so nothing shows
  -- under "No expiry date". The app warns min(7, shelf / 3) days ahead (1 day
  -- for bread or milk), which is why the "soon" rows sit where they do.
  -- ---------------------------------------------------------------------------
  insert into product_batches (shop_id, product_id, quantity, buying_price, received_on, expiry_date)
  select v_shop, d.pid, b.qty, d.buy, v_today - b.ago, v_today - b.ago + b.shelf
  from _demo d
  join (values
    -- Rice & grains
    ('Chinigura Rice',  'Pran',        6,  60,  365),
    ('Chinigura Rice',  'Pran',        8,  14,  365),
    ('Atta',            'Fresh',       6, 100,  120),
    ('Atta',            'Fresh',      10,  14,  120),
    ('Suji',            'Teer',       12,  30,  180),
    -- Cooking oil
    ('Soyabean Oil',    'Teer',        2,  14,  365),
    ('Soyabean Oil',    'Rupchanda',   7,  40,  365),
    ('Mustard Oil',     'Radhuni',    10,  60,  270),
    -- Spices
    ('Turmeric Powder', 'Radhuni',    15,  90,  365),
    ('Chilli Powder',   'Radhuni',    14,  50,  365),
    ('Cumin Powder',    'Radhuni',    10, 200,  365),
    ('Garam Masala',    'Radhuni',     8, 360,  365),  -- SOON: 5 days left
    ('Salt',            'ACI',        40,  30,  730),
    -- Cleaning & detergent
    ('Wheel Powder',    'Unilever',    9, 100,  730),
    ('Rin Powder',      'Unilever',   10,  40,  730),
    ('Vim Bar',         'Unilever',    8, 120,  730),
    ('Vim Bar',         'Unilever',   12,  14,  730),
    ('Harpic',          'Reckitt',     6, 200, 1095),
    -- Personal care
    ('Lux Soap',        'Unilever',   10, 150, 1095),
    ('Lux Soap',        'Unilever',   12,  14, 1095),
    ('Lifebuoy Soap',   'Unilever',   25,  60, 1095),
    ('Sunsilk Shampoo', 'Unilever',    8, 300,  730),
    ('Toothpaste',      'Pepsodent',  14,  80,  730),
    ('Coconut Oil',     'Parachute',  10, 100,  540),
    -- Beverages
    ('Pepsi',           'PepsiCo',     3,  14,  180),
    ('Mojo',            'Akij',       15, 175,  180),  -- SOON: 5 days left
    ('Mojo',            'Akij',       25,  14,  180),
    ('Coca-Cola',       'Coca-Cola',  12,  30,  180),
    ('Sprite',          'Coca-Cola',  30,  60,  180),
    ('Mum Water',       'Partex',     48,  20,  365),
    ('Tea',             'Ispahani',    9, 120,  540),
    -- Snacks
    ('Potato Crackers', 'Bombay',     60,  40,  120),
    ('Chanachur',       'Bombay',     20,  50,   90),
    ('Mr. Noodles',     'Square',     50,  30,  240),
    ('Energy Plus',     'Olympic',    18,  14,   74),
    ('Dairy Milk',      'Cadbury',     5, 275,  270),  -- EXPIRED 5 days ago
    ('Dairy Milk',      'Cadbury',    10,  14,  270),
    ('Fruit Cake',      'Bisk Club',   6,  10,   15),  -- SOON: 5 days left
    ('Sandwich Bread',  'Fresh Bake',  3,   5,    4),  -- EXPIRED yesterday
    ('Sandwich Bread',  'Fresh Bake',  5,   0,    3),  -- today's fresh bread
    -- Dairy
    ('Liquid Milk',     'Milk Vita',  10,   3,    4),  -- SOON: expires tomorrow
    ('Sweet Yogurt',    'Pran',        5,   3,    4),  -- SOON: expires tomorrow
    ('Farm Eggs',       'Local',      30,  15,   21),  -- SOON: 6 days left
    ('Farm Eggs',       'Local',      60,   3,   21),
    ('Milk Powder',     'Dano',        7,  90,  365),
    ('Butter',          'Aarong',      4,   7,   27),
    ('Ghee',            'Pran',        5, 120,  365)
  ) as b(name, brand, qty, ago, shelf) on b.name = d.name and b.brand = d.brand;

  -- Guard: a delivery list that claims more units than the shelf holds would
  -- make the app's expiry estimate wrong. Stop (and undo everything) if so.
  perform 1 from _demo d
    where d.stock < (select coalesce(sum(quantity), 0) from product_batches
                       where product_id = d.pid);
  if found then
    raise exception 'Demo deliveries exceed stock for some product; nothing was added.';
  end if;

  -- ---------------------------------------------------------------------------
  -- Part-payments: each customer paid back ~40% of what they owe, 2 days ago.
  -- ---------------------------------------------------------------------------
  for v_c in select id from customers where shop_id = v_shop and note = 'Demo customer' loop
    select coalesce(sum(case entry_type when 'credit_sale' then amount else -amount end), 0)
      into v_balance
      from customer_ledger where customer_id = v_c.id;
    if round(v_balance * 0.4) > 0 then
      insert into customer_ledger (shop_id, customer_id, entry_type, amount, note, created_at)
      values (v_shop, v_c.id, 'payment', round(v_balance * 0.4), 'Cash', now() - interval '2 days');
    end if;
  end loop;

  raise notice 'Demo data added to "%".', v_shop_name;
end;
$$;
