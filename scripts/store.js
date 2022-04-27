const SimpleStorage = artifacts.require('SimpleStorage');

module.exports = async (callback) => {
  try {
    const storage = await SimpleStorage.deployed();
    const reciept = await storage.set("Hello World");
    console.log(reciept);

  } catch(err) {
    console.log('Oops: ', err.message);
  }
  callback();
};