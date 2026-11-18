components { id: "screen" component: "/monarch/screen_proxy.script"
 position { x: 0 y: 0 z: 0 } rotation { x: 0 y: 0 z: 0 w: 1 }
 properties { id: "screen_id" value: "dialog" type: PROPERTY_TYPE_HASH }
 properties { id: "popup" value: "true" type: PROPERTY_TYPE_BOOLEAN }
}
components { id: "collectionproxy" component: "/examples/ui_demo/dialog.collectionproxy" position { x: 0 y: 0 z: 0 } rotation { x: 0 y: 0 z: 0 w: 1 } }
