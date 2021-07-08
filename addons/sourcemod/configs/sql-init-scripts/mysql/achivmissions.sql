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
	param_1_info text default null,
	param_2_info text default null,
	param_3_info text default null,
	param_4_info text default null,
	param_5_info text default null,
	constraint unique(name)
);

create table missi_player_data (
	id int not null,
	accountid int not null,
	progress int default null,
	plugin_data int default null,
	completed int default null,
	param_1 int default null,
	param_2 int default null,
	param_3 int default null,
	param_4 int default null,
	param_5 int default null,
	constraint unique(accountid)
);