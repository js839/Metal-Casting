-- =====================================================================
-- Metal Casting ERP - v4: Raw Material & Consumable master data
-- Source: handwritten process sheet (Scrap / FE Alloys / Electricity /
--         Melting & Pouring / Molding consumables)
-- Safe to re-run: existing codes are skipped (on conflict do nothing).
-- =====================================================================

-- 1. Allow new raw material category "Electricity"
alter table public.raw_materials drop constraint if exists raw_materials_category_check;
alter table public.raw_materials add constraint raw_materials_category_check
  check (category in ('Scrap Input', 'FE Alloy & Metal Input', 'Electricity'));

-- 2. Raw materials
insert into public.raw_materials (category, material_name, material_code, unit_of_measurement, description, status)
values
  -- Scrap Input (KG)
  ('Scrap Input', 'MS Scrap',             'RM-SCRAP-MS',    'KG', 'Mild steel scrap input.', 'Active'),
  ('Scrap Input', 'Mn Scrap',             'RM-SCRAP-MN',    'KG', 'Manganese steel scrap.', 'Active'),
  ('Scrap Input', 'Mn Scrap Grade 7',     'RM-SCRAP-MNG7',  'KG', 'Manganese scrap, grade 7.', 'Active'),
  ('Scrap Input', 'Other Scrap',          'RM-SCRAP-OTHER', 'KG', 'Miscellaneous scrap.', 'Active'),
  ('Scrap Input', 'R/R Scrap',            'RM-SCRAP-RR',    'KG', 'Runner / riser return scrap.', 'Active'),

  -- FE Alloy & Metal Input (KG)
  ('FE Alloy & Metal Input', 'Fe Mn HC',                 'RM-FE-MNHC',   'KG', 'Ferro manganese high carbon.', 'Active'),
  ('FE Alloy & Metal Input', 'Fe Si Mn',                 'RM-FE-SIMN',   'KG', 'Ferro silico manganese.', 'Active'),
  ('FE Alloy & Metal Input', 'Fe Si',                    'RM-FE-SI',     'KG', 'Ferro silicon.', 'Active'),
  ('FE Alloy & Metal Input', 'Fe Cr',                    'RM-FE-CR',     'KG', 'Ferro chrome.', 'Active'),
  ('FE Alloy & Metal Input', 'Fe Mn Low Phosphorus',     'RM-FE-MNLP',   'KG', 'Ferro manganese, low phosphorus.', 'Active'),
  ('FE Alloy & Metal Input', 'Fe Mn MC / Fe Mn LC',      'RM-FE-MNMCLC', 'KG', 'Ferro manganese medium / low carbon.', 'Active'),
  ('FE Alloy & Metal Input', 'Aluminium',                'RM-FE-AL',     'KG', 'Aluminium (deoxidiser).', 'Active'),
  ('FE Alloy & Metal Input', 'Fe Nickel',                'RM-FE-NI',     'KG', 'Ferro nickel.', 'Active'),
  ('FE Alloy & Metal Input', 'Fe Moly / Fe Vanadium',    'RM-FE-MOV',    'KG', 'Ferro molybdenum / ferro vanadium.', 'Active'),
  ('FE Alloy & Metal Input', 'Mn Metal',                 'RM-FE-MNMETAL','KG', 'Manganese metal.', 'Active'),

  -- Electricity (Unit)
  ('Electricity', 'Electricity',                         'RM-ELEC',      'Unit', 'Furnace power consumption (kWh units).', 'Active')
on conflict (material_code) do nothing;

-- 3. Consumables
insert into public.consumables (category, consumable_name, consumable_code, unit_of_measurement, description, status)
values
  -- Melting & Pouring Consumable
  ('Melting & Pouring Consumable', 'Pearlite (Slag 30)',                   'CON-MP-PEARLITE',  'KG',  'Slag coagulant.', 'Active'),
  ('Melting & Pouring Consumable', 'Argon Gas for Degassing',              'CON-MP-ARGONDG',   'KG',  'Degassing of liquid metal.', 'Active'),
  ('Melting & Pouring Consumable', 'Gas / Oil for Pre-heater',             'CON-MP-PREHEAT',   'KG',  'Ladle pre-heater fuel.', 'Active'),
  ('Melting & Pouring Consumable', 'Argon Gas for Spectrometer Analysis',  'CON-MP-ARGONSP',   'KG',  'Spectrometer argon.', 'Active'),
  ('Melting & Pouring Consumable', 'APC Powder',                           'CON-MP-APC',       'KG',  'APC powder.', 'Active'),
  ('Melting & Pouring Consumable', 'ARM',                                  'CON-MP-ARM',       'KG',  'ARM.', 'Active'),
  ('Melting & Pouring Consumable', 'BRM',                                  'CON-MP-BRM',       'KG',  'BRM.', 'Active'),
  ('Melting & Pouring Consumable', 'Y-Heat A',                             'CON-MP-YHEATA',    'KG',  'Y-Heat A.', 'Active'),
  ('Melting & Pouring Consumable', 'Spectro Paper for Polishing (Emery Paper)', 'CON-MP-SPECTRO', 'Pcs', 'Emery paper for spectro sample polishing.', 'Active'),
  ('Melting & Pouring Consumable', 'Boric Acid',                           'CON-MP-BORIC',     'KG',  'Boric acid for furnace lining.', 'Active'),
  ('Melting & Pouring Consumable', 'BRM for Patching',                     'CON-MP-BRMPATCH',  'KG',  'BRM used for patching.', 'Active'),
  ('Melting & Pouring Consumable', 'Furma for Lining of Furnace',          'CON-MP-FURMA',     'KG',  'Furnace lining material.', 'Active'),
  ('Melting & Pouring Consumable', 'Antena (CSS Antena)',                  'CON-MP-ANTENA',    'KG',  'CSS Antena.', 'Active'),
  ('Melting & Pouring Consumable', 'Asbestos Sheet',                       'CON-MP-ASBESTOS',  'Pcs', 'Asbestos sheet.', 'Active'),
  ('Melting & Pouring Consumable', 'Refractory for Bottom Pouring Ladle',  'CON-MP-REFLADLE',  'Pcs', 'Bottom pouring ladle refractory.', 'Active'),
  ('Melting & Pouring Consumable', 'Stopper for Bottom Pouring Ladle',     'CON-MP-STOPPER',   'Pcs', 'Bottom pouring ladle stopper.', 'Active'),

  -- Molding & Molding Consumable
  ('Molding & Molding Consumable', 'New Silica Sand',                      'CON-MM-NEWSAND',   'KG',  'Fresh silica sand.', 'Active'),
  ('Molding & Molding Consumable', 'Old Silica Sand',                      'CON-MM-OLDSAND',   'KG',  'Reclaimed silica sand.', 'Active'),
  ('Molding & Molding Consumable', 'Olivine Sand',                         'CON-MM-OLIVINE',   'KG',  'Olivine sand.', 'Active'),
  ('Molding & Molding Consumable', 'Zircon Sand',                          'CON-MM-ZIRCON',    'KG',  'Zircon sand.', 'Active'),
  ('Molding & Molding Consumable', 'Chromite Sand',                        'CON-MM-CHROMITE',  'KG',  'Chromite sand.', 'Active'),
  ('Molding & Molding Consumable', 'Sodium Silicate',                      'CON-MM-NASIL',     'KG',  'Binder.', 'Active'),
  ('Molding & Molding Consumable', 'CO2 Gas',                              'CON-MM-CO2',       'KG',  'CO2 for mold hardening.', 'Active'),
  ('Molding & Molding Consumable', 'Bentonite',                            'CON-MM-BENTONITE', 'KG',  'Bentonite clay.', 'Active'),
  ('Molding & Molding Consumable', 'Dextrine',                             'CON-MM-DEXTRINE',  'KG',  'Dextrine.', 'Active'),
  ('Molding & Molding Consumable', 'Exothermic Sleeve',                    'CON-MM-EXOSLEEVE', 'Pcs', 'Exothermic riser sleeve.', 'Active'),
  ('Molding & Molding Consumable', 'Mn Paint',                             'CON-MM-MNPAINT',   'KG',  'Mold coating paint.', 'Active'),
  ('Molding & Molding Consumable', 'Thinner',                              'CON-MM-THINNER',   'KG',  'Paint thinner.', 'Active'),
  ('Molding & Molding Consumable', 'Core Fix',                             'CON-MM-COREFIX',   'Box', 'Core fix (per box).', 'Active'),
  ('Molding & Molding Consumable', 'Chills',                               'CON-MM-CHILLS',    'KG',  'Chills (per kg).', 'Active'),
  ('Molding & Molding Consumable', 'Refractory for Runner Riser',          'CON-MM-REFRISER',  'Pcs', 'Runner / riser refractory.', 'Active'),
  ('Molding & Molding Consumable', 'Resin Chemical Part A',                'CON-MM-RESINA',    'KG',  'Resin binder part A.', 'Active'),
  ('Molding & Molding Consumable', 'Resin Chemical Part B',                'CON-MM-RESINB',    'KG',  'Resin binder part B.', 'Active')
on conflict (consumable_code) do nothing;
