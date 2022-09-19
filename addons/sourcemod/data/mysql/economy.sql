create table category (
	id int primary key auto_increment,
	name varchar(64) not null,
	parent int default null,
	foreign key (parent) references category(id),
	unique(name,parent)
);

create table item (
	id int primary key auto_increment,
	name varchar(64) not null,
	description varchar(64) not null,
	classname varchar(64) not null,
	price int not null,
	max_own int not null
);

create table item_category (
	item int not null,
	foreign key (item) references item(id),
	category int not null,
	foreign key (category) references category(id),
	unique(item,category)
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
	equipped tinyint not null,
	unique(accid,item,equipped)
);