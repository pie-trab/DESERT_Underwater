#ifndef UWLUMAXMODEM_H
#define UWLUMAXMODEM_H

#include <uwconnector.h>
#include <uwmodem.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

class UwLumaXModem : public UwModem
{
public:
	UwLumaXModem();
	virtual ~UwLumaXModem();

	virtual void recv(Packet *p);

	virtual int command(int argc, const char *const *argv);

	virtual int recvSyncClMsg(ClMessage *m);

	virtual double getTxDuration(Packet *p);

private:
	enum class ModemState { AVAILABLE = 0, TRANSMITTING };

	virtual void start();

	virtual void stop();

	virtual void startTx(Packet *p);

	virtual void startRx(Packet *p);

	virtual void endRx(Packet *p);

	virtual void receivingData();

	virtual void transmittingData();

	virtual void createRxPacket(Packet *p);

	virtual void completeTx(Packet *p, bool success);

	virtual bool configure();

    /** Broadcast address for the packet sending */
    std::string broadcast_address;
	/** Pointer to Connector object that interfaces with the modem for configuration */
	std::unique_ptr<UwConnector> p_modem;
	/** Pointer to Connector object that interfaces with the device for transmission */
	std::unique_ptr<UwConnector> p_connector;
	/** Variable holding the current status of the modem */
	ModemState status;
	/** Mutex associated with the state machine of the modem */
	std::mutex status_m;
	/** Mutex associated with the transmission queue */
	std::mutex tx_queue_m;
	/** Condition variable to wait for ModemState::AVAILABLE */
	std::condition_variable status_cv;
	/** Condition variable that is linked with the transmitting queue */
	std::condition_variable tx_queue_cv;
	/** Atomic boolean variable that controls the receiving looping thread */
	std::atomic<bool> receiving;
	/** Atomic boolean variable that controls the transmitting looping thread */
	std::atomic<bool> transmitting;
	/** Object with the rx thread */
	std::thread rx_thread;
	/** Object with the tx thread */
	std::thread tx_thread;
	/** String that is updated with each new received message */
	std::string rx_payload;
	/** Bitrate used only to estimate TX duration for MAC queries */
	double bitrate_;
	/** Constant duration added to each TX duration estimate */
	double tx_overhead_;

	const static std::chrono::milliseconds MODEM_TIMEOUT;
};

#endif
