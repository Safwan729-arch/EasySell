-- =============================================================================
-- Removes what demo_data.sql added from the most recently created shop: the 55
-- demo products (with ALL their sales, restocks and deliveries -- including
-- any real sale you made of those products) and the 4 demo customers with
-- their khata. Your own products and customers are untouched.
-- Covers the older 18-product demo too: those 18 are part of the 55.
-- =============================================================================
do $$
declare
  v_shop uuid;
begin
  select id into v_shop from shops order by created_at desc limit 1;

  create temp table _demo_ids on commit drop as
  select p.id from products p
  join (values
    ('Miniket Rice','Loose'), ('Nazirshail Rice','Loose'), ('Chinigura Rice','Pran'),
    ('Atta','Fresh'), ('Suji','Teer'), ('Chira','Loose'),
    ('Soyabean Oil','Teer'), ('Soyabean Oil','Rupchanda'), ('Mustard Oil','Radhuni'),
    ('Palm Oil','Loose'),
    ('Masoor Dal','Loose'), ('Mung Dal','Loose'), ('Chola','Loose'),
    ('Mashkalai Dal','Loose'),
    ('Onion','Local'), ('Potato','Local'), ('Garlic','Local'), ('Ginger','Local'),
    ('Green Chilli','Local'), ('Tomato','Local'),
    ('Turmeric Powder','Radhuni'), ('Chilli Powder','Radhuni'),
    ('Cumin Powder','Radhuni'), ('Garam Masala','Radhuni'), ('Salt','ACI'),
    ('Sugar','Loose'),
    ('Wheel Powder','Unilever'), ('Rin Powder','Unilever'), ('Vim Bar','Unilever'),
    ('Harpic','Reckitt'),
    ('Lux Soap','Unilever'), ('Lifebuoy Soap','Unilever'),
    ('Sunsilk Shampoo','Unilever'), ('Toothpaste','Pepsodent'),
    ('Coconut Oil','Parachute'),
    ('Pepsi','PepsiCo'), ('Mojo','Akij'), ('Coca-Cola','Coca-Cola'),
    ('Sprite','Coca-Cola'), ('Mum Water','Partex'), ('Tea','Ispahani'),
    ('Nescafe Classic','Nestle'),
    ('Potato Crackers','Bombay'), ('Chanachur','Bombay'), ('Mr. Noodles','Square'),
    ('Energy Plus','Olympic'), ('Dairy Milk','Cadbury'), ('Fruit Cake','Bisk Club'),
    ('Sandwich Bread','Fresh Bake'),
    ('Liquid Milk','Milk Vita'), ('Sweet Yogurt','Pran'), ('Farm Eggs','Local'),
    ('Milk Powder','Dano'), ('Butter','Aarong'), ('Ghee','Pran')
  ) as d(name, brand) on d.name = p.name and d.brand = p.brand
  where p.shop_id = v_shop;

  -- transactions -> products has no cascade, so sales go first. Deliveries
  -- cascade with the product; the khata cascades with the customer.
  delete from transactions where product_id in (select id from _demo_ids);
  delete from products     where id         in (select id from _demo_ids);
  delete from customers    where shop_id = v_shop and note = 'Demo customer';
end;
$$;
