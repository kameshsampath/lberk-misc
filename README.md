# Knative 0.9.0 with Strimzi

Installs:

* minikube 1.14.7
* Apache Kafka (via Strimzi)
* Istio Lean (1.2.x)
* Knative 0.9.0 (Serving, Eventing and the Kafka Source)

## Run the script(s)

Start the enviornment, by running the setup script:

```bash
./setup.sh
```

## Error handling

There is a known issue w/ the apply of the Knative Serving bits, you might see something like:

```bash
error: unable to recognize "STDIN": no matches for kind "Image" in version "caching.internal.knative.dev/v1alpha1"
```

That's alright and no big deal, the script will simply retry to apply the Knative Serving bits before the Knative Eventing and Kafka Sources are installed

Enjoy!