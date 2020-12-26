package whodidit

import (
	"database/sql"
	"os"

	_ "github.com/go-sql-driver/mysql"
)

type WdiDB struct {
	db              *sql.DB
	insertChangeset *sql.Stmt
	insertTile      *sql.Stmt
}

func OpenDB() *WdiDB {
	dsn := os.ExpandEnv("${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}/${MYSQL_DATABASE}")
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		panic(err)
	}
	changesets, err := db.Prepare(`
		insert into wdi_changesets
			(changeset_id, change_time, comment, user_id, user_name, created_by,
			nodes_created, nodes_modified, nodes_deleted,
			ways_created, ways_modified, ways_deleted,
			relations_created, relations_modified, relations_deleted)
			values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		on duplicate key update
			change_time = values(change_time),
			nodes_created = nodes_created + values(nodes_created),
			nodes_modified = nodes_modified + values(nodes_modified),
			nodes_deleted = nodes_deleted + values(nodes_deleted),
			ways_created = ways_created + values(ways_created),
			ways_modified = ways_modified + values(ways_modified),
			ways_deleted = ways_deleted + values(ways_deleted),
			relations_created = relations_created + values(relations_created),
			relations_modified = relations_modified + values(relations_modified),
			relations_deleted = relations_deleted + values(relations_deleted)
	`)
	if err != nil {
		panic(err)
	}
	tiles, err := db.Prepare(`
		insert into wdi_tiles
			(lat, lon, latlon, changeset_id, change_time, nodes_created, nodes_modified, nodes_deleted)
			values (?, ?, ST_SRID(Point(?,?),3857), ?, ?, ?, ?, ?)
		on duplicate key update
			nodes_created = nodes_created + values(nodes_created),
			nodes_modified = nodes_modified + values(nodes_modified),
			nodes_deleted = nodes_deleted + values(nodes_deleted)
	`)
	if err != nil {
		panic(err)
	}
	return &WdiDB{
		db,
		changesets,
		tiles,
	}
}

func (sql *WdiDB) CloseDB() {
	sql.db.Close()
}

func (sql *WdiDB) InsertDB(tiles ChangeTileCollection, cs ChangesetCollection) {
	tx, err := sql.db.Begin()
	if err != nil {
		panic(err)
	}
	for _, tile := range tiles {
		_, err := sql.insertTile.Exec(
			tile.Lat, tile.Lon,
			tile.Lat, tile.Lon,
			tile.Changeset, tile.Timestamp,
			tile.NodesCreated, tile.NodesModified, tile.NodesDeleted,
		)
		if err != nil {
			panic(err)
		}
	}
	for _, c := range cs {
		sql.insertChangeset.Exec(
			c.ID, c.Timestamp, c.Comment, c.UserID, c.User, c.CreatedBy,
			c.NodesCreated, c.NodesModified, c.NodesDeleted,
			c.WaysCreated, c.WaysModified, c.WaysDeleted,
			c.RelationsCreated, c.RelationsModified, c.RelationsDeleted,
		)
		if err != nil {
			panic(err)
		}
	}
	if err := tx.Commit(); err != nil {
		panic(err)
	}
}
