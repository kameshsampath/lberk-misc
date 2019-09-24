# Knative 0.9.0 with Strimzi

Installs:

* minikube 1.14.7
* Apache Kafka (via Strimzi)
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

That's alright and no big deal, just run the following with will continue with the setup of all Knative related bits (Serving, Eventing, Kafka Source):

```bash
./hack.sh
```

Enjoy!