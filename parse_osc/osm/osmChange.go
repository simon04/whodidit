package osm

import (
	"compress/gzip"
	"encoding/xml"
	"fmt"
	"log"
	"net/http"
	"time"
)

func GetOsmChange(id uint32) (*OsmChange, error) {
	idPadded := fmt.Sprintf("%09d", id)
	url := fmt.Sprintf("%s/minute/%s/%s/%s.osc.gz", REPLICATION_SERVER, idPadded[0:3], idPadded[3:6], idPadded[6:9])
	log.Printf("Fetching %s...", url)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "whodidit")

	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()

	reader, err := gzip.NewReader(res.Body)
	if err != nil {
		return nil, err
	}

	var osmChange OsmChange
	if err := xml.NewDecoder(reader).Decode(&osmChange); err != nil {
		return nil, err
	}
	return &osmChange, nil
}

type OsmChange struct {
	Version   string      `xml:"version,attr"`
	Generator string      `xml:"generator,attr"`
	Delete    []OsmAction `xml:"delete"`
	Modify    []OsmAction `xml:"modify"`
	Create    []OsmAction `xml:"create"`
}

type OsmAction struct {
	Node     []OsmPrimitive `xml:"node"`
	Way      []OsmPrimitive `xml:"way"`
	Relation []OsmPrimitive `xml:"relation"`
}

type OsmPrimitive struct {
	ID        uint64    `xml:"id,attr"`
	Version   uint16    `xml:"version,attr"`
	Timestamp time.Time `xml:"timestamp,attr"`
	UserID    uint64    `xml:"uid,attr"`
	User      string    `xml:"user,attr"`
	Changeset uint32    `xml:"changeset,attr"`
	Lat       float64   `xml:"lat,attr"`
	Lon       float64   `xml:"lon,attr"`
	Node      []struct {
		Ref uint64 `xml:"ref,attr"`
	} `xml:"nd"`
	Member []struct {
		Type string `xml:"type,attr"`
		Ref  uint64 `xml:"ref,attr"`
		Role string `xml:"role,attr"`
	} `xml:"member"`
	Tag []OsmTag `xml:"tag"`
}

type OsmTag struct {
	Key   string `xml:"k,attr"`
	Value string `xml:"v,attr"`
}

func (tag OsmTag) String() string {
	return fmt.Sprintf("%s=%s", tag.Key, tag.Value)
}
