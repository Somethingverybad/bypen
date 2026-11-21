package main

import "time"

func waitSec(n int) { time.Sleep(time.Duration(n) * time.Second) }
