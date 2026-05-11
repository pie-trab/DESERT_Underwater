

#ifndef UWLUMAXMODEM_H
#define UWLUMAXMODEM_H

#include <uwconnector.h>
#include <uwmodem.h>

#include <atomic>
#include <condition_variable>
#include <map>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

class UwLumaXModem: public UwModem
{
public: 
	UwLumaXModem();
	virtual ~UwLumaXModem();

private:
	virtual void recv(Packet *p);
	
	virtual void startTx(Packet *p);
	
	virtual void startRx(Packet *p);
	
	virtual void endRx(Packet *p);

	virtual void receivingData();;
	
	/** Pointer to Connector object that interfaces with the device */
	std::unique_ptr<UwConnector> p_connector;
	// /** Pointer to Interpreter object to parse device syntax */
	// std::unique_ptr<UwInterpreterS2C> p_interpreter;
	/** Mutex associated with the state machine of the modem */
	std::mutex status_m;
	/** Mutex associated with the transmission state machine of the modem */
	std::mutex tx_status_m;
	/** Mutex associated with the transmission queue */
	std::mutex tx_queue_m;
	/** Condition variable to wait for ModemState::AVAILABLE */
	std::condition_variable status_cv;
	/** Condition variable to wait for TransmissionState::TX_IDLE */
	std::condition_variable tx_status_cv;
	/** Condition variable that is linked with the transmitting queue */
	std::condition_variable tx_queue_cv;


	
};

#endif
