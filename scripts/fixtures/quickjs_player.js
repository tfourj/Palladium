// Synthetic player exercising EJS preprocessing and both challenge types.
(function () {
    function MediaURL(signature) {
        this.values = {s: signature};
    }
    MediaURL.prototype.set = function (key, value) {
        this.values[key] = value;
    };
    MediaURL.prototype.get = function (key) {
        return this.values[key];
    };
    MediaURL.prototype.solve = function () {
        if (typeof this.values.n === "string") {
            this.values.n = this.values.n.split("").reverse().join("");
        }
        if (typeof this.values.s === "string") {
            this.values.s = this.values.s.slice(1);
        }
    };
    function makeURL(url, key, signature) {
        var result = new MediaURL(signature);
        result.set("alr", "yes");
        return result;
    }
}).call(this);
