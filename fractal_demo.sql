-- First, run this .sql file to load data into the cells table and to create
-- the functions/procedures.  Then, you can play around with the demo by
-- SELECTing from the mandelbrot_colors() table valued function.  Try
-- running this zsh command for an interesting progression of fractals:

-- zsh -c 'i=3.0; while ((i > 0.0000000001)) && mysql -h 127.0.0.1 -u root -P 3306 --database db <<<"select * from mandelbrot_colors(-0.743643887103515, 0.131825914205310, $i)"; do echo $i; ((i = i /2)); done'

-- You can also pass in a fourth and fifth argument to the mandelobrot_colors function in order to 
-- increase the number of pixels.

-- We want 1 byte chars so we can maximize the width of our
-- picture. Group concat has at most 8k bytes, so 1 byte
-- chars and 16 bytes per pixel (of color sequences) gives
-- us a max width of ~500 pixels.
--
set global collation_server = "binary";
set collation_server = "binary";

create database if not exists db;
use db;
create table if not exists cells(r int, c int, primary key rc(r, c));
delimiter //

create or replace procedure fill_cells()
as
declare
    _size query(size int) = select count(*) as size from cells;
    size int = scalar(_size);
begin
    if size = 0 then
        for r in 0 .. 1500 loop
            insert ignore into cells values (r, 0);
        end loop;
        insert ignore into cells
            select t1.r, t2.r
            from cells as t1, cells as t2
            where t2.r != 0;
    end if;
end //
call fill_cells() //

create or replace function p1(r int, c int)
returns int
as
begin
    return r;
end //

create or replace function p2(r int, c int)
returns int
as
begin
    return c;
end //

create or replace function complex_double(z record(r double, i double))
returns double
as
begin
    return z.r;
end //

create or replace function complex_imaginary(z record(r double, i double))
returns double
as
begin
    return z.i;
end //

create or replace function complex_size(c record(r double, i double))
returns double
as
begin
    return sqrt(c.r*c.r + c.i*c.i);
end //

create or replace function complex_mult(a record(r double, i double),b record(r double, i double))
returns record(r double, i double)
as
begin
    return row(a.r * b.r - a.i * b.i, a.r * b.i + b.r * a.i);
end //

create or replace function complex_add(a record(r double, i double), b record(r double, i double))
returns record(r double, i double)
as
begin
    return row(a.r + b.r, a.i + b.i);
end //

create or replace function complex_sub(a record(r double, i double), b record(r double, i double))
returns record(r double, i double)
as
begin
    return row(a.r - b.r, a.i - b.i);
end //

create or replace function mandelbrot_dist(c record(r double, i double),
                                           maxiters int default 10000)
returns int
as
declare
    z record(r double, i double) not null = row(0, 0);
begin
    for i in 1 .. maxiters loop
        if complex_size(z) > 2.0 then
            return i;
        end if;
        z = complex_add(complex_mult(z, z), c);
    end loop;
    return maxiters;
end //

create or replace function mandelbrot_scale(r int, c int, maxr int, maxc int,
                                            cx double, cy double, width double)
returns record(r double, i double)
as
declare
    aspect_ratio double = (maxc :> double) / (maxr :> double);
    xadjust double = (width/2);
    -- Multiply by 2 because most characters are 2x as
    -- many pixels high as they are wide.
    yadjust double = xadjust / aspect_ratio * 2; 
    minz record(r double, i double) = row(cx - xadjust, cy - yadjust);
    maxz record(r double, i double) = row(cx + xadjust, cy + yadjust);
    gap record(r double, i double) = complex_sub(maxz, minz);
begin
    return complex_add(minz, row(gap.r * c/maxc, gap.i * (maxr - r - 1)/maxr));
end //

create or replace function bgcolor(color int)
returns mediumtext
as
begin
    return CONCAT(UNHEX("1b"), '[48;5;', LPAD(color, 3, "0"), 'm', " ", UNHEX("1b"), '[0m');
end //

create or replace function mandelbrot_char_colors(iters int)
returns mediumtext
as
declare
    options array(varchar(24)) = 
        [17, 4, 18, 19, 20, 21,  -- dark blue -> blue
         63, 105, 147, 189, 231, 230, 229,
         228, 227, 226, 220, 214, 208,
         202, 196, 160, 124, 88, 52];
    i int = (sqrt(iters * sqrt(iters)) :> int) % length(options);
begin
    if iters >= 10000 then
        return bgcolor(16);
    else
        return bgcolor(options[i]);
    end if;
end //

create or replace function mandelbrot_char(iters int)
returns varchar(24)
as
declare
    options array(varchar(24)) = 
    [' ', '.', '*', "@", "#"];
    i int = (iters / 10000 * (length(options) - 1)) :> int;
begin
    return options[i];
end //

create or replace function complex_str(z record(r double, i double))
returns text
as
begin
    return LPAD(CONCAT(FORMAT(z.r, 1),
                       IF(z.i < 0, "", "+"),
                       FORMAT(z.i, 1), "i"), 10, " ");
end //

create or replace function complex_grid(height int default 6,
                                        width int default 6)
returns table
as return select group_concat(complex_str(mandelbrot_scale(r, c, height, width, -0.5, 0, 3)) separator ", ") as line, rr
        from (
            select *, rank() over(order by c) rr
            from cells
            where r < height and c < width
        ) q1
        group by r
        order by r
        limit height //

create or replace function mandelbrot_dist_grid(height int default 20,
                                                width int default 25)
returns table
as return select group_concat(LPAD(mandelbrot_dist(mandelbrot_scale(r, c, height, width, -0.5, 0, 3), 10), 2, " ") separator ", ") as line, rr
        from (
            select *, rank() over(order by c) rr
            from cells
            where r < height and c < width
        ) q1
        group by r
        order by r
        limit height //


create or replace function mandelbrot(cx double default -0.5,
                                      cy double default 0,
                                      scale double default 3,
                                      height int default 20,
                                      width int default 72)
returns table
as return select group_concat(mandelbrot_char(dist) separator "") as line, rr
        from (
            select *,
                   mandelbrot_dist(mandelbrot_scale(r, c, height, width, cx, cy, scale)) as dist,
                   rank() over(order by c) rr
            from cells
            where r < height and c < width
        ) q1
        group by r
        order by r
        limit height //

create or replace function mandelbrot_colors(cx double default -0.5,
                                             cy double default 0,
                                             scale double default 3,
                                             height int default 20,
                                             width int default 72)
returns table 
as return select group_concat(mandelbrot_char_colors(dist) separator "") as line, rr
        from (
            select *, mandelbrot_dist(mandelbrot_scale(r, c, height, width, cx, cy, scale)) as dist, rank() over(order by c) rr
            from cells
            where r < height and c < width
        ) q1
        group by r
        order by r
        limit height //

delimiter ;

