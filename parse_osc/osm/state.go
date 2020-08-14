package osm

import (
	"bufio"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
)

const REPLICATION_SERVER = "https://planet.openstreetmap.org/replication"

func GetServerState() (int, error) {
	url := REPLICATION_SERVER + "/minute/state.txt"
	log.Printf("Fetching %s...", url)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return -1, err
	}
	req.Header.Set("User-Agent", "whodidit")

	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return -1, err
	}
	defer res.Body.Close()

	scanner := bufio.NewScanner(res.Body)
	scanner.Split(bufio.ScanLines)
	var serverState int
	for scanner.Scan() {
		text := scanner.Text()
		if !strings.HasPrefix(text, "sequenceNumber=") {
			continue
		}
		numberString := text[len("sequenceNumber="):]
		serverState, _ = strconv.Atoi(numberString)
		return serverState, nil
	}
	return -1, fmt.Errorf("sequenceNumber= not found")
}
