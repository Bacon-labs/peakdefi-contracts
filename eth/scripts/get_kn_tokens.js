// Generated by CoffeeScript 2.3.0
(function() {
  /*
      For fetching token metadata using a list of token symbols/tickers
      Input format:
      [
          "OMG",
          "KNC",
          ...
      ]
      Output format:
      [
          {
              name: Token,
              symbol: TKN,
              decimals: 18
          },
          ...
      ]
  */
  var fs, https, main, wait,
    indexOf = [].indexOf;

  https = require("https");

  fs = require("fs");

  wait = function(time) {
    return new Promise(function(resolve) {
      return setTimeout(resolve, time);
    });
  };

  main = async function() {
    var allTokens, apiStr, data, i, knTokenSymbols, len, ref, token, tokens;
    knTokenSymbols = require("../deployment_configs/kn_token_symbols.json");
    allTokens = require("../scripts/ethTokens.json");
    tokens = [];
    for (i = 0, len = allTokens.length; i < len; i++) {
      token = allTokens[i];
      if (ref = token.symbol, indexOf.call(knTokenSymbols, ref) >= 0) { // and token.decimal >= 11
        apiStr = `https://api.ethplorer.io/getTokenInfo/${token.address}?apiKey=freekey`;
        data = (await (new Promise(function(resolve, reject) {
          return https.get(apiStr, function(res) {
            var rawData;
            rawData = "";
            res.on("data", function(chunk) {
              return rawData += chunk;
            });
            return res.on("end", function() {
              var parsedData;
              parsedData = JSON.parse(rawData);
              return resolve(parsedData);
            });
          }).on("error", reject);
        })));
        tokens.push({
          name: data.name,
          symbol: token.symbol,
          decimals: token.decimal
        });
        console.log(data.name);
        await wait(2000);
      }
    }
    return fs.writeFileSync("./eth/deployment_configs/kn_tokens.json", JSON.stringify(tokens));
  };

  main();

}).call(this);
