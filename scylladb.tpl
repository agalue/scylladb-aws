{
  "scylla_yaml": {
    "cluster_name": "${cluster_name}",
    "num_tokens": 16,
    "seed_provider": [
      {
        "class_name": "org.apache.cassandra.locator.SimpleSeedProvider",
        "parameters": [
          { "seeds": "${seed}" }
        ]
      }
    ]
  },
  "post_configuration_script": "${post_config}",
  "start_scylla_on_first_boot": true
}