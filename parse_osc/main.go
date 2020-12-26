package main

import (
	"fmt"
	"log"

	"github.com/simon04/whodidit/parse_osc/osm"
	"github.com/simon04/whodidit/parse_osc/whodidit"
)

func main() {
	db := whodidit.OpenDB()
	defer db.CloseDB()

	serverState := osm.GetServerState()
	fmt.Println("Server state", serverState)

	id := osm.GetLocalState()
	fmt.Println("Local state", id)

	for id = id + 1; id <= serverState; id = id + 1 {
		osmChange, err := osm.GetOsmChange(uint32(id))
		if err != nil {
			panic(err)
		}
		changesets, err := osm.GetChangesetsForOsmChange(osmChange)
		if err != nil {
			panic(err)
		}
		tiles, cs := whodidit.GetChangeTiles(osmChange, changesets)
		log.Printf("Inserting change %d into database...", id)
		db.InsertDB(tiles, cs)
		osm.WriteLocalState(id)
	}
}
