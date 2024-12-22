CREATE TABLE `wdi_changesets` (
  `changeset_id` int(10) unsigned NOT NULL,
  `change_time` datetime NOT NULL,
  `comment` varchar(254) DEFAULT NULL,
  `user_id` int(10) unsigned NOT NULL,
  `user_name` varchar(96) NOT NULL,
  `created_by` varchar(64) DEFAULT NULL,
  `nodes_created` smallint(5) unsigned NOT NULL,
  `nodes_modified` smallint(5) unsigned NOT NULL,
  `nodes_deleted` smallint(5) unsigned NOT NULL,
  `ways_created` smallint(5) unsigned NOT NULL,
  `ways_modified` smallint(5) unsigned NOT NULL,
  `ways_deleted` smallint(5) unsigned NOT NULL,
  `relations_created` smallint(5) unsigned NOT NULL,
  `relations_modified` smallint(5) unsigned NOT NULL,
  `relations_deleted` smallint(5) unsigned NOT NULL,
  PRIMARY KEY (`changeset_id`),
  KEY `idx_user` (`user_name`),
  KEY `idx_time` (`change_time`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

CREATE TABLE `wdi_tiles` (
  `lat` smallint(6) NOT NULL,
  `lon` smallint(6) NOT NULL,
  `latlon` point NOT NULL,
  `changeset_id` int(10) unsigned NOT NULL,
  `change_time` datetime NOT NULL,
  `nodes_created` smallint(5) unsigned NOT NULL,
  `nodes_modified` smallint(5) unsigned NOT NULL,
  `nodes_deleted` smallint(5) unsigned NOT NULL,
  PRIMARY KEY (`changeset_id`,`lat`,`lon`),
  SPATIAL KEY `idx_latlon` (`latlon`),
  KEY `idx_time` (`change_time`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;
