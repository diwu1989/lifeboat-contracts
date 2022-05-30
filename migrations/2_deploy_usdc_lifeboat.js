const Lifeboat = artifacts.require("Lifeboat");

module.exports = function (deployer) {
  const swappa = "0xF35ed7156BABF2541E032B3bB8625210316e2832";
  const oracle = "0xDA7a001b254CD22e46d3eAB04d937489c93174C3";
  const limit = "1000000000000000000000";
  const cusd = "0x765DE816845861e75A25fCA122bb6898B8B1282a";
  const usdc = "0xef4229c8c3250C675F21BCefa42f58EfbfF6002a";
  const depot = "0x436bC8C741b55864B40A0D3B6f2B6eCB5771B5AA";
  const oracleBase = "CUSD";
  const oracleQuote = "USD";
  // deployed to 0x0D2dB8611C7730B7e0423b1F6b0C817D200d9d08
  deployer.deploy(Lifeboat,
    swappa,
    oracle,
    limit,
    cusd,
    usdc,
    depot,
    oracleBase,
    oracleQuote);
};
