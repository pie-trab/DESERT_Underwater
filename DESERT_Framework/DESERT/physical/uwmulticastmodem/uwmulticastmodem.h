
#ifndef UWMULTICASTMODEM_H
#define UWMULTICASTMODEM_H

#include <netinet/in.h>
#include <packet.h>
#include <uwmodem.h>
#include <uwsocket.h>

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <thread>

class UwMulticastModem : public UwModem
{
public:
	enum class ModemState { AVAILABLE = 0, TRANSMITTING, RECEIVING };

	UwMulticastModem();

	virtual ~UwMulticastModem();

	virtual void recv(Packet *p);

	/**
	 * Tcl command interpreter: Method that maps Tcl commands into C++ methods.
	 *
	 * @param argc number of arguments in <i> argv </i>
	 * @param argv array of strings which are the command parameters
	 * 		  (Note that <i>argv[0]</i> is the name of the object).
	 * @return TCL_OK or TCL_ERROR whether the command has been dispatched
	 *		   successfully or not
	 */
	virtual int command(int argc, const char *const *argv);

	/**
	 * Method that returns the modulation type used for the packet being
	 * transmitted. Inherited from MPhy, in NS-MIRACLE, could be left empty if
	 * no way exists to retrieve this information
	 * @param p Packet pointer to the given packet being transmitted
	 * @param modulation type represented by an integer
	 */
	virtual int getModulationType(Packet *p); // TODO

	virtual double getTxDuration(Packet *p); // TODOp

	/**
	 * Cross-Layer messages synchronous interpreter.
	 *
	 * @param ClMessage* an instance of ClMessage that represent the
	 * message received
	 * @return <i>0</i> if successful.
	 */
	virtual int recvSyncClMsg(ClMessage *m);

protected:
	/**  */
	virtual void startTx(Packet *p);

	virtual void startRx(Packet *p);

	virtual void endRx(Packet *p);

	/** Variable holding the current status of the modem */
	ModemState status;

private:
	/**
	 * Initialize and start the driver operation, opens the connection for
	 * transmission and reception in separate threads
	 */
	virtual void start();

	/** Close connection to modem and stops threads */
	virtual void stop();

	/**
	 * Method that dispatch a thread dedicated to receiving data from the data
	 * connector
	 */
	virtual void receivingData();

	/**
	 * Method that dispatches a thread dedicated to transmitting data through
	 * the data connector
	 */
	virtual void transmittingData();

	/**
	 * Method that creates a packet from the received stream of bytes
	 * @param p allocated empty packet to fill in with the received bytes
	 */
	virtual void createRxPacket(Packet *p);

	virtual void completeTx(Packet *p, bool success);

	virtual bool configure();

	/** Address for data connection, in format XXX.XXX.XXX.XXX:PORT */
	std::string data_address;

	// TODO this specific behaviour is relative to the LUMAX modem, see if this
	// can change the name to the class back to the LumaX thig that was
	// originally
	/** Socket connector for modem configuration  */
	std::unique_ptr<UwConnector> modem_connector;
	/** Pointer to Connector object that interfaces with the device for
	 * transmission */
	std::unique_ptr<UwConnector> data_connector;
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
	/** Object with the configuration thread */
	std::thread configuration_thread;
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
	/** Size of messages */
	int message_size;

	const static std::chrono::milliseconds MODEM_TIMEOUT;
};

#endif