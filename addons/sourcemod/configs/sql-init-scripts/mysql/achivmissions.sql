create table achiv_data (
	id int not null primary key auto_increment,
	name text not null,
	max int default null,
	constraint unique(name)
);

create table achiv_player_data (
	id int not null,
	accountid int not null,
	progress int default null,
	plugin_data int default null,
	achieved int default null,
	constraint unique(id,accountid)
);

create table achiv_display (
	id int not null,
	description text default null,
	image text default null,
	hidden int default null,
	constraint unique(id)
);

create table missi_data (
	id int not null primary key auto_increment,
	name text not null,
	description text default null,
	extra_data_1 text default null,
	extra_data_2 text default null,
	extra_data_3 text default null,
	extra_data_4 text default null,
	extra_data_5 text default null,
	constraint unique(name)
);

create table missi_player_data (
	id int not null,
	accountid int not null,
	progress int default null,
	plugin_data int default null,
	completed int default null,
	extra_data_1 int default null,
	extra_data_2 int default null,
	extra_data_3 int default null,
	extra_data_4 int default null,
	extra_data_5 int default null,
	constraint unique(accountid)
);