create table item_category (
	id int primary key auto_increment,
	name varchar(64) not null,
	parent int default null,
	foreign key (parent) references item_category(id)
);

create table item (
	id int primary key auto_increment,
	category int not null,
	foreign key (category) references item_category(id),
	name varchar(64) not null,
	description varchar(64) not null,
	classname varchar(64) not null,
	price int not null
);

create table item_setting (
	item int not null,
	foreign key (item) references item(id),
	name varchar(64) not null,
	value varchar(64) not null,
	unique(item,name)
);

create table player_currency (
	accid int primary key,
	amount int not null
);

create table player_inventory (
	id int primary key auto_increment,
	accid int not null,
	item int not null,
	foreign key (item) references item(id),
	equipped tinyint not null
);