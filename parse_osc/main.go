package main

import (
	"fmt"

	"github.com/simon04/whodidit/parse_osc/osm"
	"github.com/simon04/whodidit/parse_osc/whodidit"
)

func main() {
	fmt.Println("Hello World!")
	serverState, _ := osm.GetServerState()
	fmt.Println(serverState)
	osmChange, err := osm.GetOsmChange(4024000)
	if err != nil {
		panic(err)
	}
	changesets, err := osm.GetChangesetsForOsmChange(osmChange)
	if err != nil {
		panic(err)
	}

	tiles, cs := whodidit.GetChangeTiles(osmChange, changesets)
	db := whodidit.OpenDB()
	defer db.CloseDB()
	db.InsertDB(tiles, cs)
}
