--Данные:
--Ссылка на резервную копию в формате *.backup: avia.backup. Восстанавливаете, как и предыдущие данные, согласно "Инструкции по установке ПО".
--В облачной базе данных работаете с базой даных total и схемой bookings. Доступ только на чтение, все необходимые модули установлены.
--Описание БД:
--Ссылка на описание демонстрационной базы данных: "Авиаперевозки".

--=============== Задания: ===============

--1. Выведите название самолетов, которые имеют менее 50 посадочных мест?
--2. Выведите процентное изменение ежемесячной суммы бронирования билетов, округленной до сотых.
--3. Выведите названия самолетов не имеющих бизнес - класс. Решение должно быть через функцию array_agg.
--4. Найдите процентное соотношение перелетов по маршрутам от общего количества перелетов.
-- Выведите в результат названия аэропортов и процентное отношение.
-- Решение должно быть через оконную функцию.
--5. Выведите количество пассажиров по каждому коду сотового оператора, если учесть, что код оператора - это три символа после +7
--6. Классифицируйте финансовые обороты (сумма стоимости перелетов) по маршрутам:
-- До 50 млн - low
-- От 50 млн включительно до 150 млн - middle
-- От 150 млн включительно - high
-- Выведите в результат количество маршрутов в каждом полученном классе
--7. Вычислите медиану стоимости перелетов, медиану размера бронирования и отношение медианы бронирования к медиане стоимости перелетов, округленной до сотых
--8. Найдите значение минимальной стоимости полета 1 км для пассажиров. То есть нужно найти расстояние между аэропортами и с учетом стоимости перелетов получить искомый результат
--  Для поиска расстояния между двумя точками на поверхности Земли используется модуль earthdistance.
--  Для работы модуля earthdistance необходимо предварительно установить модуль cube.
--  Установка модулей происходит через команду: create extension название_модуля.

--Пояснения:
--Перелет, рейс - разовое перемещение самолета из аэропорта А в аэропорт Б.
--Маршрут - формируется двумя аэропортами А и Б. При этом А - Б и Б - А - это разные маршруты.

--=============== Решение: ===============
set search_path to bookings;


--1. Выведите название самолетов, которые имеют менее 50 посадочных мест.
/*
К тблице aircrafts с названиями (моделями) самолетов присоединим таблицу seats по общему полю aircraft_code.
Далее сгруппируем строки по aircraft_code и для каждой группы подсчитаем количество мест фнукцией count. 
Оставим строки с количеством мест строго меньшим 50. 
 */

select a.model, count(s.seat_no)
from aircrafts a
join seats s using (aircraft_code)
group by a.aircraft_code
having count(s.seat_no) < 50

--2. Выведите процентное изменение ежемесячной суммы бронирования билетов, округленной до сотых.
/*
Процентное изменение будем искать по формуле:
(сумма за тек. месяц - сумма за предыдущий месяц)*100 / сумма за предыдущий месяц

Из таблицы booking даты "обрезаем" функцией date_trunc (оставляем год и месяц), группируем в порядке от ранней к поздней,
для каждой группы суммируем значения total_amount.
Считаем процентное изменение, при этом сумму за предыдущий месяц подсчитываем оконной функцией lag (NULL по 
умолчанию на 0 не заменяем, чтобы избежать ошибки деления на 0);
чтобы в случае отсутствия данных за отдельные месяцы вычисления выполнялись корректно (и текущий месяц 
всё равно сравнивался с предыдущим), в сортировку добавляем строку 
<range between '1 month' preceding and current row>. 
Формулу оборачиваем функцией round для округления.
 */
--explain analyze --cost=26896.48..29842.05 rows=56106 width=72) (actual time=159.794..180.802 rows=3 loops=1)
select date_trunc('month', book_date), sum(total_amount), 
round((sum(total_amount) - lag(sum(total_amount)) over w_1 ) * 100 / lag(sum(total_amount)) over w_1, 2) as "percentage"
from bookings
group by date_trunc('month', book_date)
window w_1 as (order by date_trunc('month', book_date) range between '1 month' preceding and current row) 


/*
 Вариант решения с помощью рекурсии (более ресурсозатратный).
 */
--explain analyze --cost=82384.04..82405.78 rows=8696 width=76) (actual time=262.715..262.779 rows=3 loops=1)
with recursive r as (
	--стартовая часть
	select min(date_trunc('month', book_date)) x
	from bookings
	union
	--рекурсивная часть
	select x + interval '1 month' as x
	from r 
	where x < (select max(date_trunc('month', book_date)) from bookings)
	)
select x::date, coalesce(b.sum, 0.),
coalesce(round((coalesce(b.sum, 0.) - lag(coalesce(b.sum, 0.)) over w_1 ) * 100. / lag(coalesce(b.sum, 0.)) over w_1, 2), 0.) as "percentage"
from r
left join (
	select date_trunc('month', book_date), sum(total_amount)
	from bookings b 
	group by date_trunc('month', book_date)) b 
	on b.date_trunc = r.x
window w_1 as (order by x)
order by 1


--3. Выведите названия самолетов не имеющих бизнес - класс. Решение должно быть через функцию array_agg.

/*
 Таблицу aircrafts соединяем с таблицей seats по aircraft_code, строки группируем по aircraft_code, 
 для каждой группы функцией array_agg создаем массив из значений fare_conditions.
 Условием 'Business' != all(array_agg(s.fare_conditions)) оставляем только те строки, в которых места класса
 'Business' отсутствуют (сочетание оператора != и функции all даст True только для тех массивов, в которых нет 
 элемента 'Business').
 Выводим модели самолетов и их коды.
 */

--explain analyze --HashAggregate  (cost=34.46..34.69 rows=9 width=48) (actual time=0.622..0.653 rows=2 loops=1)
select a.model, a.aircraft_code 
from aircrafts a
join seats s on a.aircraft_code = s.aircraft_code
group by a.aircraft_code 
having 'Business' != all(array_agg(s.fare_conditions))

/*
 Решение с помощью подзапроса. 
 В подзапросе из таблицы seats строки группируем по aircraft_code, для каждой группы формируем масссив из значений
 fare_conditions, условием 'Business' != all(array_agg(s.fare_conditions)) оставляем самолеты без бизнесс-класса.
 Результаты подзапроса соединяем с таблицей aircrafts по aircraft_code, выводим модели самолетов и их коды.
 
 Данное решение менее ресурсозатратно, чем предыдущее.
 */

--explain analyze --Hash Join  (cost=28.51..29.64 rows=9 width=48) (actual time=0.424..0.425 rows=2 loops=1)
select a.model, a.aircraft_code 
from (
	select aircraft_code
	from seats
	group by aircraft_code
	having 'Business' != all(array_agg(fare_conditions))
	) f
join aircrafts a
on f.aircraft_code = a.aircraft_code


--4. Найдите процентное соотношение перелетов по маршрутам от общего количества перелетов.
-- Выведите в результат названия аэропортов и процентное отношение.
-- Решение должно быть через оконную функцию.

/*
 Таблицу flights соединяем с таблицей airports два раза: один раз по коду аэропорта отправления, второй - по коду 
 аэропорта прибытия, чтобы получить названия аэропортов отправления и прибытия соответственно. Условием в where
 убираем из вывода отмененные рейсы.
 Оконной функцией count подсчитываем количество flight_id, сгруппированных по маршрутам (т.е. по совокупности 
 departure_airport плюс arrival_airport), а также общее количество рейсов. Для каждого маршрута вычисляем процентное отношение и 
 округляем его.
 */

--explain analyze --Unique  (cost=7368.66..7695.65 rows=32699 width=74) (actual time=261.532..279.179 rows=618 loops=1)
select distinct ad.airport_name as "departure_airport", aa.airport_name as "arrival_airport",
round((count(f.flight_id) over w_1 * 100. / count(*) over()), 3) as "Percentage"
from flights f
join airports ad on f.departure_airport = ad.airport_code
join airports aa on f.arrival_airport = aa.airport_code
where f.status != 'Cancelled'
window w_1 as (partition by f.departure_airport, f.arrival_airport)
--order by "departure_airport"


--5. Выведите количество пассажиров по каждому коду сотового оператора, если учесть,
--что код оператора - это три символа после +7

/*
 Тип данных в колонке contact_data - jsonb. Командой substring((contact_data ->> 'phone')::text from 3 for 3 
 из столбца contact_data получаем phone_code: по ключу 'phone' получаем строку с номером телефона, 
 преобразуем ее в текст и "вырезаем" три символа начиная с третьего.
 Функцией count подсчитываем количество passenger_id, сгруппированных по полученным выше кодам. 
 */

select count(passenger_id) as number_of_passengers, substring((contact_data ->> 'phone')::text from 3 for 3) as phone_code
from tickets
group by substring((contact_data ->> 'phone') from 3 for 3)


--6. Классифицируйте финансовые обороты (сумма стоимости перелетов) по маршрутам:
-- До 50 млн - low
-- От 50 млн включительно до 150 млн - middle
-- От 150 млн включительно - high
-- Выведите в результат количество маршрутов в каждом полученном классе

/*
 Формируем подзапрос: к таблице flights присоединяем таблицу ticket_flights по flight_id,
 группируем строки по совокупности f.departure_airport плюс f.arrival_airport, для групп подсчитываем суммы 
 стоимости билетов, добавляем столбец flight_cost с результатми классификации по стоимости.
 Строки из подзапроса группируем по flight_cost и для каждого результата классификаци функцией count подсчитываем количество строк.
 */

--explain analyze --(cost=20684.26..20711.10 rows=200 width=40) (actual time=261.546..279.837 rows=3 loops=1)
select flight_cost, count(*)
from (
	select f.departure_airport, f.arrival_airport, sum(amount),
	case 
		when sum(amount) < 50000000 then 'low'
		when sum(amount) >= 50000000 and sum(amount) < 150000000 then 'middle'
		else 'high'
	end flight_cost
	from flights f
	join ticket_flights tf using (flight_id)
	group by f.departure_airport, f.arrival_airport
) sub
group by flight_cost


--7. Вычислите медиану стоимости перелетов, медиану размера бронирования и отношение 
--медианы бронирования к медиане стоимости перелетов, округленной до сотых.

/*
 Решение с помощью CTE. В cte_b и cte_f находим медианы, затем подсчитываем их отношение, округляем его.
 */

--explain analyze --Nested Loop  (cost=30016.72..30016.77 rows=1 width=48) (actual time=720.364..720.366 rows=1 loops=1)
with cte_b as (
	select percentile_cont(0.5) within group (order by total_amount) as book_med
	from bookings),
cte_f as (
	select percentile_cont(0.5) within group (order by amount) as flight_med
	from ticket_flights)
select cte_b.book_med, cte_f.flight_med, round((cte_b.book_med / cte_f.flight_med)::numeric, 2) as median_ratio 
from cte_b, cte_f


/*
 Второй вариант решения - с помощью материализованного представления (более ресурсозатратный).
 */

create materialized view mv_b as
	select percentile_cont(0.5) within group (order by total_amount) as book_med
	from bookings
with data

create materialized view mv_f as
	select percentile_cont(0.5) within group (order by amount) as flight_med
	from ticket_flights
with data

--explain analyze --(cost=0.00..76684.85 rows=5107600 width=24) (actual time=0.023..0.025 rows=1 loops=1)
select mv_b.book_med, mv_f.flight_med, round((mv_b.book_med / mv_f.flight_med)::numeric, 2) as median_ratio 
from mv_b, mv_f

--8. Найдите значение минимальной стоимости полета 1 км для пассажиров. 
--То есть нужно найти расстояние между аэропортами и с учетом стоимости перелетов получить искомый результат.
--  Для поиска расстояния между двумя точками на поверхности Земли используется модуль earthdistance.
--  Для работы модуля earthdistance необходимо предварительно установить модуль cube.
--  Установка модулей происходит через команду: create extension название_модуля.

create extension cube;
create extension earthdistance;

/*
 Т.к. в таблице ticket_flights более миллиона строк, сначала уменьшим ее избыточность, для этого 
 в подзапросе stf получим минимальные суммы перелетов и их flight_id (останется 22226 строк).
 К таблице flights присоединим два раза таблицу airports по f.arrival_airport = aa.airport_code (чтобы привязать широту и долготу к 
 аэропорту прибытия) и по f.departure_airport = ad.airport_code (аналогично для аэропорта отправления).
 Далее к полученному датасету присоединяем результат подзапроса stf по flight_id.
 Для вывода искомого значения вычисляем для всех строк отношение минимальной стоимости перелета к расстоянию по сфере Земли в км, затем
 функцией min находим минимальное, округляем его.
 */

--explain analyze --Aggregate  (cost=32486.79..32486.81 rows=1 width=32) (actual time=507.290..507.353 rows=1 loops=1)
select round(min(stf.min/((earth_distance (ll_to_earth (ad.latitude, ad.longitude), ll_to_earth (aa.latitude, aa.longitude)))/1000 ))::numeric, 2)
from flights f
join airports aa on f.arrival_airport = aa.airport_code
join airports ad on f.departure_airport = ad.airport_code
join (
	select flight_id, min(amount)
	from ticket_flights
	group by flight_id
	) stf
on stf.flight_id = f.flight_id

