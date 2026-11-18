components { id: "screen" component: "/monarch/screen_proxy.script"
 position { x: 0 y: 0 z: 0 } rotation { x: 0 y: 0 z: 0 w: 1 }
 properties { id: "screen_id" value: "upgrade" type: PROPERTY_TYPE_HASH }
 
}
components { id: "collectionproxy" component: "/examples/miner/upgrade.collectionproxy" position { x: 0 y: 0 z: 0 } rotation { x: 0 y: 0 z: 0 w: 1 } }
